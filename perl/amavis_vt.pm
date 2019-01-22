# Amavis_VT VirusTotal - Scanner for AmavisD
# @author Franz Dürr
# @author Dr. Michael Wagner (initial version)
# @version 1.65
# @date 2018-12-10
# TODO: put log-db-writing into my_vt and let my_vt schedule VT-calls so 204-errors are avoided altogether
# requires that $dbh is global. vt_log could be used to schedule the calls

# Installation by hand:
# apt install sqlite3 libdbi-perl libdbd-sqlite3-perl libjson-perl libfile-libmagic-perl
# copy this file to /usr/share/perl5/:
#   cp amavis_vt.pm /usr/share/perl5/
# add the following entry to the @av_scanners - array defined in /etc/amavis/conf.d/15-avscanners:
#   ['Amavis_VT', sub { use amavis_vt; Amavis::AV::ask_av(\&amavis_vt::check_file, @_) }, ["{}/*"], [0], [1], qr/^(.*)$/m ]
# create config file /etc/amavis_vt.cf (must at least contain a line with $api_key):
# (to obtain an API-key from Google, see https://developers.virustotal.com/v2.0/reference)
#   $api_key = "3e7a...";
#   1;
# check syntax and restart amavid - daemon:
# (CAVEAT: If script contains syntax errors when Amavis  is restarted, Amavis will not start, therefore the syntax check!)
#   perl -cw -Mstrict /usr/share/perl5/amavis_vt.pm && service amavis restart

#TABLE STRUCTURE vt_scan:
# hash VARCHAR(255) PRIMARY KEY
# mimetype VARCHAR(255)
# created TIMESTAMP DEFAULT CURRENT_TIMESTAMP
# tstamp UNSIGNED BIGINT
# cnt UNSIGNED SMALLINT
# hits UNSIGNED SMALLINT
# details TEXT
# scan_date TIMESTAMP

#TABLE STRUCTURE vt_log:
# tstamp UNSIGNED BIGINT
# http_code UNSIGNED SMALLINT
# hash32 UNSIGNED INTEGER

package amavis_vt;

use strict;
use warnings;

use DBI;  # requires SQLite 3.3+
use Digest::SHA;
use File::LibMagic qw();
use File::stat;
use JSON;
use LWP::UserAgent;
use Sys::Syslog qw(:standard :macros);
use open qw< :encoding(UTF-8) >;
use Fcntl qw< LOCK_EX >;
#use POSIX qw(strftime); # CAVEAT: fduerr_2018-03-16: use of strftime() crashes script!! dont know why..

# define configuration default values adjustable by config file
our $config_file = '/etc/amavis_vt.cf';
our $disabled = 0; # quick way to disable amavis_vt
our $db_dsn   = 'SQLite:/var/lib/amavis/amavis_vt.db';
our $db_table = 'vt_scan';
our $db_log_table = 'vt_log';
our $db_user = '';
our $db_pass = '';
our $sleep_seconds = 2; # sleep interval while waiting for result
our $timeout_seconds = 90; # max waiting time for result (at least $retry_204 * 60 + 10)
our $retry_204 = 1; # how many times to retry HTTP code 204 'exceeded rate limit' in 60 second intervals
our $min_file_size = 100;
our $max_file_size = 0; # 0 = unlimited
our $log_tag = 'amavis_vt';
our $log_verbosity = 1; # 0 = no logging, 1 = default, 2 = verbose, 3 = debug
our $log_level = LOG_INFO;  # LOG_INFO, LOG_NOTICE, LOG_WARN, LOG_ERR, -1 to print log messages
our $log_facility = LOG_MAIL;
our $threshold = 2; # hits to trigger exploit return
our @forbid_files = (); # forbid files with these mime types (always return as infected)
our @scan_only_files = ();  # array of regular expressions for mime types to process exclusively
our @dont_scan_files = ('^text\/(plain|html)', '^image\/(jpeg|png|gif)', 'application\/pgp-signature'); # array of regular expressions for mime types to ignore
our @greylist_files = ();  # array of regular expressions for mime types to greylist (e.g. if not listed in VT, wait $greylist_minutes and check again)
our $greylist_minutes = 0; # greylist interval, after which file is scanned again
our $die_if_undef = 0;	# 0 to return [0, 'clean'] if result is undefined, 1 to die instead (CAVEAT: not sure if '1' may cause Amavis to ignore consecutive results fd_20180617)
our $rescan_after_minutes = 30; # 0 to disable rescan
our $rescan_negatives = 1;  # rescan negatives that many times (0 to disable rescans, better use at least 1 to catch brand new malware)
our $rescan_positives = 0;  # rescan positives that many times (if 0, positives found in DB are never rescanned e.g. once positive, always positive)
our $max_virus_names = 10; # 0 for unlimited
our $white_list = ''; # path to file with hashes that are to be inserted as permanent negatives into db (used to avoid VT-calls for CPS-made PDFs)
our $api_url = 'https://www.virustotal.com/vtapi/v2/file/report';
our $api_key = '';

# my_log($msg[,$verbosity_level=1])
# if verbosity_level = 0, die!
sub my_log {
	my $lvl = defined $_[1] ? $_[1] : 1;
	if ($log_level >= 0) {
	  syslog($log_level | $log_facility, "$log_tag $$: ".($lvl == 0 ? 'FATAL ' : '').$_[0]) unless $lvl > $log_verbosity;
	} else {
	  print "$log_tag $$: ".($lvl == 0 ? 'FATAL ' : '').$_[0]."\n" unless $lvl > $log_verbosity;
	}
	die($_[0]) if $lvl == 0;
}

# my_vt($hash)
sub my_vt {
	my $r = LWP::UserAgent->new(ssl_opts => {verify_hostname => 1})->post($api_url, ['apikey' => $api_key, 'resource' => $_[0]]);
	my_log('VT HTTP no return', 0) unless $r;
	my_log('VT HTTP code='.$r->code.' success='.$r->is_success.' content='.$r->content, 3);
	return $r;
}

# exit status: 0:clean; 1:exploit; 2:corrupted
sub check_file($;@) {

	# include configuration and check if disabled
	require "$config_file" unless !$config_file;
	my_log("disabled in $config_file", 0) if $disabled;

	# get file name, check MIME type and file size
	my @result = (0, 'Clean');
	my ($file_name) = @_;
	my $file_size = -s $file_name;
	my_log("cannot get file size for $file_name", 0) unless $file_size;
	
	my $mime_type = File::LibMagic->new->checktype_filename($file_name);
	$mime_type =~ s/ *;.*//;  # cut off charset info

	if (@forbid_files && ( grep { $mime_type =~ /$_/ } @forbid_files )) {
		my_log("forbid $file_name $mime_type size=$file_size return [1,'Virus: $mime_type']");
		return (1, "Virus: $mime_type");
	}
	
	if ($file_size < $min_file_size || ($max_file_size > 0 && $file_size > $max_file_size)
		|| (@scan_only_files && !( grep { $mime_type =~ /$_/ } @scan_only_files ))
		|| (@dont_scan_files && ( grep { $mime_type =~ /$_/ } @dont_scan_files ))) {
		if ($die_if_undef) {
			my_log("exclude $file_name $mime_type size=$file_size", 2);
			die;
		}
		my_log("exclude $file_name $mime_type size=$file_size return [".$result[0].",'".$result[1]."']", 2);
		return @result;
	}
	
	# calculate SHA1 key and log
	my $hash = Digest::SHA->new(1)->addfile($file_name)->hexdigest;
	my_log("can't open $file_name", 0) unless $hash;
	my_log("check $file_name $mime_type size=$file_size SHA1=$hash");
	my $h32 = hex(substr($hash, -8));	# rightmost 8 hex digits of hash as unsigned integer

	# if database support is enabled, ensure that lookup table exists and check whether hash is already recorded
	# important: DBI must be configured to return errors e.g. RaiseError => 0
	my $dbh;
	my $sth;
	if ($db_dsn && $db_table) {
		# open database and create table if required (creates SQLite database file if it doesn't exist)
	  $dbh = DBI->connect("DBI:$db_dsn", $db_user, $db_pass, { PrintError => 0, RaiseError => 0 });
	  if ($dbh &&	$dbh->do(
	  	"CREATE TABLE IF NOT EXISTS $db_table(hash VARCHAR(255) PRIMARY KEY, mimetype VARCHAR(255), created TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    	scan_date TIMESTAMP, tstamp UNSIGNED BIGINT, cnt UNSIGNED SMALLINT, hits UNSIGNED SMALLINT, details TEXT)")) {
    	if ($db_log_table) {	# logs calls to VirusTotal and the HTTP result code
    		$dbh->do("CREATE TABLE IF NOT EXISTS $db_log_table(tstamp UNSIGNED BIGINT, http_code UNSIGNED SMALLINT, hash32 UNSIGNED INTEGER);");
    		#	$dbh->do("CREATE INDEX IF NOT EXISTS ".$db_log_table."_tstamp_idx ON $db_log_table(tstamp)");
	    	# log for statistics
				$dbh->do("INSERT INTO $db_log_table(tstamp,http_code,hash32) VALUES (".time().",0,$h32)");
    	}
    	
    	# check if whitelist must be processed
    	# list consist of lines with 2 elments separated by a space: <hash> <mime_type>
    	# this allows processes with write access to that list to whitelist hashes not to be checked against VT
    	# CAVEAT: amavis needs write access to whitelist, so if used with CPS, user 'amavis' must be member of group 'checkpoint'
    	if ($white_list) {
    		#my_log('getgrname='.getgrnam('checkpoint'));
    		#$) .= ' '.getgrnam('checkpoint'); # or: setgid(getgrnam('checkpoint'));
    		my_log(sprintf("open whitelist $white_list perm=%04o effUID=$> effGID=$)", (stat($white_list))[2] & 07777), 3);
    		if (!open(my $fh, '+<', $white_list)) {
					my_log(sprintf("whitelist open($white_list) failed: $! perm=%04o effUID=$> effGID=$)", (stat($white_list))[2] & 07777));
				} elsif (!flock($fh, LOCK_EX)) {
					my_log("whitelist exclusive lock($white_list) failed: $!");
					close $fh;
				} else {
  	  		# read whitelist into array and clear it
    			chomp(my @lines = <$fh>);
					seek $fh, 0, 0;
					truncate $fh, 0;
					close $fh;
					my $lines = @lines;
					my_log("whitelist $white_list with $lines elements", 3);
					# process array - enter all hashes as negative with big count
					if ($lines > 0) {
			    	my $is_white = 0;	# set to true if current hash in white_list to avoid unnecessary INSERT-attempt
						$sth = $dbh->prepare("INSERT INTO $db_table(hash,mimetype,created,scan_date,tstamp,hits,cnt) VALUES (?,?,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP,?,0,999)");
						foreach (@lines) {
							my @words = split / /, "$_ octet-stream";
							my_log("INSERT from whitelist $_", 2);
							my_log("INSERT from whitelist failed for ".$words[0]) unless $words[0] =~ /^[0-9a-f]{40,}$/ && $sth->execute($words[0], $words[1], time());
							$is_white |= ($words[0] eq $hash);
						}
						if ($is_white) {
							$dbh->do("INSERT INTO $db_log_table(tstamp,http_code,hash32) VALUES (".time().",10,$h32)") if ($db_log_table);	# log whitelist returns with http_code=10
							my_log('return white ['.$result[0].",'".$result[1]."']");
							return @result;
						}
					}
				}
    	}
    	
    	# look whether file hash already recorded by inserting the hash record
      my_log("try INSERT $hash in database $db_table", 3);
			$sth = $dbh->prepare("INSERT INTO $db_table(created,cnt,mimetype,hash) VALUES (CURRENT_TIMESTAMP,0,?,?)");
			if ($sth->execute($mime_type, $hash)) {	# if successful, this is the first VT-query for this hash
				my_log("INSERT $hash OK", 3);
			} else { # VT-query already done or in progress
				my $rec;
				my_log("INSERT $hash ERR (".$DBI::err.' '.$DBI::errstr."), waiting max $timeout_seconds seconds for record with cnt>0..", 3);
				$sth = $dbh->prepare("SELECT * FROM $db_table WHERE cnt>0 AND hash=?");
				for (my $n = 0; $n < $timeout_seconds && (!$sth->execute($hash) || !($rec = $sth->fetchrow_hashref())); $n += $sleep_seconds) {
					sleep($sleep_seconds);
				}
				if ($rec && $rec->{'hits'} < 65535) {
			  	my $ts = $rec->{'tstamp'};
		  		my $hits = $rec->{'hits'};
		  		my $code = ($hits >= $threshold ? 1 : 0);	# CAVEAT: rescan is enforced if DB entry has hits > 0 but < treshold, as perhaps there are more hits now
		  		if ($ts > (time() - $rescan_after_minutes * 60) || ($rec->{'cnt'} > ($code > 0 ? $rescan_positives : $rescan_negatives) && ($hits == 0 || $code > 0))) {
						$dbh->do("INSERT INTO $db_log_table(tstamp,http_code,hash32) VALUES (".time().','.(20+$code).",$h32)") if ($db_log_table);	# log database returns with http_code=20/21
		  			@result = ($code, ($code > 0 ? "Virus: " : "")."$hash Hits=$hits ".$rec->{'details'});
				  	my_log("return database result [$code,'".$result[1]."'] cnt=".$rec->{'cnt'});
				  	return @result;
					} else {
          	my_log("database result for $hash=$hits, recheck with VT!", 2);
					}
				} elsif ($rec) {	# unprocessed
         	my_log("database result for $hash unprocessed (hits=65535), recheck with VT!");
				} else {	# timeout
					my_log("timeout after waiting $timeout_seconds seconds for $hash with cnt>0");
				}
			}
    } else {
      my_log('database error on CREATE '.$DBI::err.' '.$DBI::errstr); # log database error and continue
      undef $dbh;
    }
	}

	# use VirusTotal API to ask about file
	my_log("VT HTTP query $api_url", 3);
	my $ts = time();
	my $response = my_vt($hash);
	my $log_codes = "($ts,".$response->code.",$h32)";
	my $retries = 0;
	while ($response->code == 204 && $retries++ < $retry_204) {	# request rate limit exceeded (max 4/min), wait 60 seconds and try again
		my_log("VT request rate limit exceeded (max 4/min) - waiting 60 seconds", 3);
		sleep(60);
		$response = my_vt($hash);
		$log_codes .= ',('.time().','.$response->code.",$h32)";
	}

	my $ret;
	if ($response->code == 200) {	# VT success
		$ret = ' ';
		my $wait_sec = 90; # assume processing
		my $vt = JSON->new->allow_nonref->decode($response->content);
		my $rc = int($vt->{response_code});	# 0 = not found, 1 = found, -2 = processing
		# if file not found and to be greylisted
		if ($rc == 0 && $greylist_minutes > 0 && ( grep { $mime_type =~ /$_/ } @greylist_files )) {
			$rc = -2; # enforce rescan
			$wait_sec = $greylist_minutes * 60;
			my_log("$mime_type greylisted for $greylist_minutes minutes");
		}
		while ($rc == -2) {	# processing or greylisted
			sleep($wait_sec);
			$response = my_vt($hash);
			$log_codes .= ',('.time().','.$response->code.",$h32)";
			my_log("VT HTTP code=".$response->code, 0) unless $response->code == 200;
			$vt = JSON->new->allow_nonref->decode($response->content);
			$rc = int($vt->{response_code});
			$wait_sec = 90;
		}
		my $hits = int($vt->{positives});
		my $rtext = '';
		my_log("VT result for $hash: RC=$rc Hits=$hits");
		
		if ($hits > 0) {	# if hits were found, build result
			# virus: traverse scans and collect names of virus for scanners that detected a virus
			my $ntext = 0;
			my $scans = $vt->{scans};
			foreach (keys(%$scans)) {
				my $t = $scans->{$_}->{result};
				if ($t) {
					$rtext .= "|$_:$t";
					last if (++$ntext == $max_virus_names);
				}
			}
			$rtext = substr($rtext, 1);
			if ($hits >= $threshold) {
				@result = (1, "Virus: $hash Hits=$hits $rtext");
				my_log("VT found malware: Hits=$hits >= $threshold $rtext");
			} else {
				my_log("VT found hits: $hash Hits=$hits < $threshold $rtext");
			}
		}

	  # if database support is enabled, update hash record
	  if ($dbh) {
    	my $sth = $dbh->prepare("UPDATE $db_table SET tstamp=?,scan_date=?,mimetype=?,hits=?,details=?,cnt=cnt+1 WHERE hash=?");
    	if ($sth && $sth->execute($ts, $vt->{scan_date}, $mime_type, $hits, $rtext, $hash)) {
				my_log("UPDATE $hash OK Hits=$hits Details=$rtext");
			} else {
      	my_log("UPDATE $hash ERR ".$DBI::err.' '.$DBI::errstr, 1); # log database error and continue
			}
		}
		
	} elsif ($dbh) {	# VT fail with DB handling
		# if this is the first try for the hash, we mark the entry as unprocessed by setting hits=65535
		# otherwise we return the old record content as result (better than nothing..)
		my $sth = $dbh->prepare("UPDATE $db_table SET tstamp=?,hits=65535,cnt=1 WHERE hash=? AND cnt=0"); # mark as unprocessed
		if (!$sth->execute($ts, $hash)) { # no unprocessed record, try to get old record 
			$sth = $dbh->prepare("SELECT * FROM $db_table WHERE cnt>0 AND hits<65535 AND hash=?");
			if ($sth->execute($hash) && (my $rec = $sth->fetchrow_hashref())) {
	  		my $hits = $rec->{'hits'};
	  		my $code = ($hits >= $threshold ? 1 : 0);
  			@result = ($code, ($code > 0 ? "Virus: " : "")."$hash Hits=$hits ".$rec->{'details'});
		  	$ret = 'previous result ';
			}
		}
	}

	$dbh->do("INSERT INTO $db_log_table(tstamp,http_code,hash32) VALUES ".$log_codes.',('.time().','.($response->code == 200 ? 30 + $result[0] : 99).",$h32)") if ($db_log_table && $dbh);
	my_log("VT fail code=".$response->code, 0) if $die_if_undef && !$ret;
	my_log('return '.($ret ? $ret : 'undetermined ').'['.$result[0].",'".$result[1]."']");
	return @result;
}

1;
