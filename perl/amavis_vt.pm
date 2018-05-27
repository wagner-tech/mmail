# VirusTotal - Scanner for AmavisD
# @date 2017-11-01
# @author Dr. Michael Wagner
# @author Franz Dürr
# @version 0.8
# @date 2017-11-11

# Installation by hand:
# copy this file to /usr/share/perl5/
#   cp amavis_vt.pm /usr/share/perl5/
# add the following entry to the @av_scanners - array defined in /etc/amavis/conf.d/15-avscanners:
#   ['mmail-vt', sub { use amavis_vt; Amavis::AV::ask_av(\&amavis_vt::check_file, @_) }, ["{}/*"], [0], [1], qr/^(Virus:.*)$/m ]
# create config file /etc/amavis_vt.cf (must al least contain a line with $api_key):
#   $api_key = "3e7a...";
#   1;
# restart amavid - daemon:
#   service amavisd restart

package amavis_vt;

use strict;
use warnings;

use DBI;  # requires SQLite 3.3+
use Digest::SHA;
use File::LibMagic qw();
use JSON;
use LWP::UserAgent;
use Sys::Syslog qw(:standard :macros);

# define module constants
our $config_file = '/etc/amavis_vt.cf';
our @ret_ok = (0, 'Clean');
our $dbh;
our $rec;

# define configuration default values
# all of these can be adjusted in the config file
our $db_driver   = 'SQLite';
our $db_file = '/var/lib/amavis/amavis_vt.db';
our $db_table = 'vt_scan';
our $db_user = '';
our $db_pass = '';
our $min_file_size = 100;
our $max_file_size = 0;
our $log_verbosity = 1; # 0 = no logging, 1 = default, 2 = verbose, 3 = debug
our $log_level = LOG_INFO;  # LOG_INFO, LOG_NOTICE, LOG_WARN, LOG_ERR
our $log_facility = LOG_MAIL;
our $threshold = 2; # hits to trigger exploit return
our @forbid_files = (); # forbid files with these mime types (always return as infected)
our @scan_only_files = ();  # array of regular expressions for mime types to process exclusively
our @dont_scan_files = ('^text\/', '^image\/'); # array of regular expressions for mime types to ignore
our $rescan_after_hours = 2; # 0 to disable rescan
our $rescan_negatives = 2;  # rescan negatives that many times (0 to disable, better use at least 1 to catch brand new malware)
our $rescan_positives = 0;  # rescan positives that many time (if 0, positives found in DB are never rescanned e.g. once positive, always positive)
our $max_virus_names = 5; # 0 for unlimited
our $api_url = 'https://www.virustotal.com/vtapi/v2/file/report';
our $api_key = '';

# my_log($msg[,$verbosity_level=1])
sub my_log {
  syslog($log_level | $log_facility, 'amavis_vt: '.$_[0]) unless ($_[1] ? $_[1] : 1) > $log_verbosity;
}

# exit status: 0:clean; 1:exploit; 2:corrupted
sub check_file($;@) {

	# include configuration
	require "$config_file";

	my($fn) = @_;  # file name to be checked

	# check MIME type and file size
	my $file_size = -s $fn;
	my $mime_type = File::LibMagic->new->checktype_filename($fn);
	$mime_type =~ s/ *;.*//;  # cut off charset info
	if (@forbid_files && ( grep { $mime_type =~ /$_/ } @forbid_files )) {
		my_log("forbid $fn $mime_type size=$file_size");
		return (1, "FORBID $mime_type");
	}
	if ($file_size < $min_file_size || ($max_file_size > 0 && $file_size > $max_file_size)
		|| (@scan_only_files && !( grep { $mime_type =~ /$_/ } @scan_only_files ))
		|| (@dont_scan_files && ( grep { $mime_type =~ /$_/ } @dont_scan_files ))) {
		my_log("exclude $fn $mime_type size=$file_size", 2);
		return @ret_ok;
	}
	
	# calculate SHA1 key and log
	my $hash = Digest::SHA->new(1)->addfile($fn)->hexdigest;
	die ("cannot open $fn") unless $hash;
	my_log("check $fn $mime_type size=$file_size SHA1=$hash");

	# if database support is enabled, check whether hash is already in db
	if ($db_file) {
		# open database and create table if required
	  $dbh = DBI->connect("DBI:$db_driver:$db_file", $db_user, $db_pass, { RaiseError => 1 }) or die $DBI::errstr;
    $dbh->do("CREATE TABLE IF NOT EXISTS $db_table(hash VARCHAR(255) PRIMARY KEY, mimetype VARCHAR(255), created TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    	scan_date TIMESTAMP, tstamp UNSIGNED BIGINT, cnt UNSIGNED SMALLINT, hits UNSIGNED SMALLINT, details TEXT)") or die $DBI::errstr;
    # look whether file hash already recorded
		my $sth = $dbh->prepare("SELECT * FROM $db_table WHERE hash=?");
		if ($sth->execute($hash)) {
		  if ($rec = $sth->fetchrow_hashref()) {
		  	my $ts = $rec->{'tstamp'};
		  	my $hits = $rec->{'hits'};
        my $code = ($hits >= $threshold ? 1 : 0);	# CAVEAT: rescan is enforced if DB entry has hits > 0 but < treshold, as perhaps there are more hits now
			  if ($ts > (time() - $rescan_after_hours * 3600) || ($rec->{'cnt'} > ($code > 0 ? $rescan_positives : $rescan_negatives) && ($hits == 0 || $code > 0))) {
				  my_log("return database result $code for $hash tstamp=$ts hits=$hits ".$rec->{'details'});
				  return ($code, $rec->{'details'});
			  } else {
          my_log("recheck database result for $hash tstamp=$ts", 2);
        }
		  }
    } else {
      my_log('database error '.$DBI::errstr, 1); # log database error and continue
    }
	}

	# use VirusTotal API to ask about file
	my @result = @ret_ok;
	my $response = LWP::UserAgent->new(ssl_opts => {verify_hostname => 1})->post($api_url, ['apikey' => $api_key, 'resource' => $hash]);
	my_log("VT HTTP code=".$response->code." success=".$response->is_success." content=".$response->content, 3);
	die ("VT fail code=".$response->code) unless ($response->is_success);
	my $vt = JSON->new->allow_nonref->decode($response->content);
	my $hits = int($vt->{positives});
	my $rtext = '';
	my_log("VT result for $hash: hits=$hits");

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
			@result = (1, $rtext);
			my_log("VT found malware: hits=$hits >= $threshold $rtext");
		} else {
			my_log("VT found hits: hits=$hits < $threshold $rtext");
		}
	}

  # if database support is enabled, insert / update hash record
	if ($dbh) {
    my $sth = $dbh->prepare($rec ?
      "UPDATE $db_table SET tstamp=?,scan_date=?,mimetype=?,hits=?,details=?,cnt=cnt+1 WHERE hash=?" :
      "INSERT INTO $db_table(created,tstamp,scan_date,mimetype,hits,details,hash,cnt) VALUES (CURRENT_TIMESTAMP,?,?,?,?,?,1)");
    $sth->execute(time(), $vt->{scan_date}, $mime_type, $hits, $rtext, $hash);
		my_log(($rec ? "update" : "insert")." database SHA1=$hash hits=$hits result=$rtext", 2);
	}
	return @result;
}

1;
