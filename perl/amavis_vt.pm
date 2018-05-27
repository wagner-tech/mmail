# VirusTotal - Scanner for AmavisD
# @author Dr. Michael Wagner
# @author Franz Dürr
# @version 1.1
# @date 2018-04-26
# @todo The public VT-API allows only 4 requests per minute: Detect if a request was denied due to that limit and postpone it to the next minute

# Installation by hand:
# apt install sqlite3 libdbi-perl libdbd-sqlite3-perl libjson-perl libfile-libmagic-perl
# copy this file to /usr/share/perl5/:
#   cp amavis_vt.pm /usr/share/perl5/
# add the following entry to the @av_scanners - array defined in /etc/amavis/conf.d/15-avscanners:
#   ['mmail-vt', sub { use amavis_vt; Amavis::AV::ask_av(\&amavis_vt::check_file, @_) }, ["{}/*"], [0], [1], qr/^(.*)$/m ]
# create config file /etc/amavis_vt.cf (must al least contain a line with $api_key):
# (to obtain an API-key, see https://developers.virustotal.com/v2.0/reference)
#   $api_key = "3e7a...";
#   1;
# check syntax and restart amavid - daemon:
# (CAVEAT: If script contains syntax errors when Amavis  is restarted, Amavis will not start, therefore the syntax check!)
#   perl -cw -Mstrict /usr/share/perl5/amavis_vt.pm && service amavis restart

package amavis_vt;

use strict;
use warnings;

use DBI;  # requires SQLite 3.3+
use Digest::SHA;
use File::LibMagic qw();
use JSON;
use LWP::UserAgent;
use Sys::Syslog qw(:standard :macros);
#use POSIX qw(strftime); # CAVEAT: fduerr_2018-03-16: use of strftime() crashes script!! dont know why..

# define module vars
our $config_file = '/etc/amavis_vt.cf';
our @result = (0, 'Clean');
our $dbh;
our $sth;
our $rec;

# define configuration default values
# all of these can be adjusted in the config file
our $db_dsn   = 'SQLite:/var/lib/amavis/amavis_vt.db';
our $db_table = 'vt_scan';
our $db_user = '';
our $db_pass = '';
our $sleep_seconds = 2; # sleep interval while waiting for result
our $timeout_seconds = 60; # max waiting time for result
our $min_file_size = 100;
our $max_file_size = 0; # 0 = unlimited
our $log_verbosity = 1; # 0 = no logging, 1 = default, 2 = verbose, 3 = debug
our $log_level = LOG_INFO;  # LOG_INFO, LOG_NOTICE, LOG_WARN, LOG_ERR
our $log_facility = LOG_MAIL;
our $threshold = 2; # hits to trigger exploit return
our @forbid_files = (); # forbid files with these mime types (always return as infected)
our @scan_only_files = ();  # array of regular expressions for mime types to process exclusively
our @dont_scan_files = ('^text\/', '^image\/', 'application\/pgp-signature'); # array of regular expressions for mime types to ignore
our $rescan_after_hours = 2; # 0 to disable rescan
our $rescan_negatives = 2;  # rescan negatives that many times (0 to disable rescans, better use at least 1 to catch brand new malware)
our $rescan_positives = 0;  # rescan positives that many time (if 0, positives found in DB are never rescanned e.g. once positive, always positive)
our $max_virus_names = 5; # 0 for unlimited
our $api_url = 'https://www.virustotal.com/vtapi/v2/file/report';
our $api_key = '';

# my_log($msg[,$verbosity_level=1])
# if verbosity_level = 0, die!
sub my_log {
	my $lvl = defined $_[1] ? $_[1] : 1;
	if ($log_level >= 0) {
	  syslog($log_level | $log_facility, 'amavis_vt: '.($lvl == 0 ? 'FATAL ' : '').$_[0]) unless $lvl > $log_verbosity;
	} else {
	  print 'amavis_vt: '.($lvl == 0 ? 'FATAL ' : '').$_[0]."\n" unless $lvl > $log_verbosity;
	}
	die($_[0]) unless $lvl > 0;
}

# exit status: 0:clean; 1:exploit; 2:corrupted
sub check_file($;@) {

	# include configuration
	require "$config_file" unless !$config_file;

	my($fn) = @_;  # file name to be checked

	# check MIME type and file size
	my $file_size = -s $fn;
	my_log("cannot get file size for $fn", 0) unless $file_size;
	
	my $mime_type = File::LibMagic->new->checktype_filename($fn);
	$mime_type =~ s/ *;.*//;  # cut off charset info

	if (@forbid_files && ( grep { $mime_type =~ /$_/ } @forbid_files )) {
		my_log("forbid $fn $mime_type size=$file_size return [1,'Virus: $mime_type']");
		return (1, "Virus: $mime_type");
	}
	if ($file_size < $min_file_size || ($max_file_size > 0 && $file_size > $max_file_size)
		|| (@scan_only_files && !( grep { $mime_type =~ /$_/ } @scan_only_files ))
		|| (@dont_scan_files && ( grep { $mime_type =~ /$_/ } @dont_scan_files ))) {
		my_log("exclude $fn $mime_type size=$file_size return [".$result[0].",'".$result[1]."']", 2);
		return @result;
	}
	
	# calculate SHA1 key and log
	my $hash = Digest::SHA->new(1)->addfile($fn)->hexdigest;
	my_log("cannot open $fn", 0) unless $hash;
	my_log("check $fn $mime_type size=$file_size SHA1=$hash");

	# if database support is enabled, ensure that lookup table exists and check whether hash is already recorded
	# important: DBI must be configured to return errors e.g. RaiseError => 0
	if ($db_dsn) {
		# open database and create table if required (creates SQLite database file if it doesn't exist)
	  $dbh = DBI->connect("DBI:$db_dsn", $db_user, $db_pass, { PrintError => 0, RaiseError => 0 });
	  if ($dbh &&	$dbh->do(
	  	"CREATE TABLE IF NOT EXISTS $db_table(hash VARCHAR(255) PRIMARY KEY, mimetype VARCHAR(255), created TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    	scan_date TIMESTAMP, tstamp UNSIGNED BIGINT, cnt UNSIGNED SMALLINT, hits UNSIGNED SMALLINT, details TEXT)")) {
    	# look whether file hash already recorded by inserting the hash record
      my_log("try INSERT $hash in database $db_table", 3);
			$sth = $dbh->prepare("INSERT INTO $db_table(created,cnt,mimetype,hash) VALUES (CURRENT_TIMESTAMP,0,?,?)");
			if ($sth->execute($mime_type, $hash)) {	# if successful, this is the first VT-query for this hash
				my_log("INSERT $hash OK", 3);
			} else { # VT-query already done or in progress
				my_log("INSERT $hash ERR (".$DBI::err.' '.$DBI::errstr."), waiting max $timeout_seconds seconds for record with cnt>0..", 3);
				$sth = $dbh->prepare("SELECT * FROM $db_table WHERE cnt>0 AND hash=?");
				for (my $n = 0; $n < $timeout_seconds && (!$sth->execute($hash) || !($rec = $sth->fetchrow_hashref())); $n += $sleep_seconds) {
					sleep($sleep_seconds);
				}
				if ($rec) {
			  	my $ts = $rec->{'tstamp'};
		  		my $hits = $rec->{'hits'};
		  		my $code = ($hits >= $threshold ? 1 : 0);	# CAVEAT: rescan is enforced if DB entry has hits > 0 but < treshold, as perhaps there are more hits now
		  		if ($ts > (time() - $rescan_after_hours * 3600) || ($rec->{'cnt'} > ($code > 0 ? $rescan_positives : $rescan_negatives) && ($hits == 0 || $code > 0))) {
				  	my_log("return database result $code for $hash Hits=$hits ".$rec->{'details'});
				  	return ($code, ($code > 0 ? "Virus: " : "")."$hash Hits=$hits ".$rec->{'details'});
					} else {
          	my_log("database result for $hash=$hits, recheck with VT!", 2);
					}
				} else {	# timeout
					my_log("timeout after waiting $timeout_seconds seconds for $hash with cnt>0", 1);
				}
			}
    } else {
      my_log('database error on CREATE '.$DBI::err.' '.$DBI::errstr, 1); # log database error and continue
      undef $dbh;
    }
	}

	# use VirusTotal API to ask about file
	my $ts = time();
	my_log("VT HTTP query $api_url", 3);
	my $response = LWP::UserAgent->new(ssl_opts => {verify_hostname => 1})->post($api_url, ['apikey' => $api_key, 'resource' => $hash]);
	my_log("VT HTTP code=".$response->code." success=".$response->is_success." content=".$response->content, 3);
	my_log("VT fail code=".$response->code, 0) unless $response->is_success;
	my $vt = JSON->new->allow_nonref->decode($response->content);
	my $hits = int($vt->{positives});
	my $rtext = '';
	my_log("VT result for $hash: Hits=$hits");

	# build result if hits were found
	if ($vt->{response_code} > 0 && $hits > 0) {
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
    $sth = $dbh->prepare("UPDATE $db_table SET tstamp=?,scan_date=?,mimetype=?,hits=?,details=?,cnt=cnt+1 WHERE hash=?");
		if ($sth && $sth->execute($ts, $vt->{scan_date}, $mime_type, $hits, $rtext, $hash)) {
			my_log("UPDATE $hash OK Hits=$hits Details=$rtext");
	  } else {
      my_log("UPDATE $hash ERR ".$DBI::err.' '.$DBI::errstr, 1); # log database error and continue
	  }
	}
	my_log('return ['.$result[0].",'".$result[1]."']", 3);
	return @result;
}

1;
