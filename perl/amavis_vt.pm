package amavis_vt;

use strict;
use warnings;

use DBI;
use Digest::SHA;
use File::LibMagic qw();
use JSON;
use LWP::UserAgent;
use Sys::Syslog qw(:standard :macros);

use VTScan;

# define module constants
our $default_config_file = "/etc/amavis_vt.cf";
our @ret_ok = (0, "Clean");

# define config file var
our $config_file;

# define configuration default values
our $db_file = "/var/lib/amavis/amavis-vt.db";
our $api_key = "";
our $min_file_size = 100;
our $log_level = 1;
our $threshold = 2;
our @scan_only_files = ();
our @dont_scan_files = ('^text\/', '^image\/');
our $rescan_after_hours = 10;
our $url='https://www.virustotal.com/vtapi/v2/file/report';

sub my_log {
    my $msg = shift;
    syslog(LOG_INFO, "amavis_vt: $msg") unless $log_level eq 0;
}

# set config file with module parameter
sub import {
	my ($package, $file) = @_;
	$file = $default_config_file unless ($file);
	$config_file = $file;
}

sub open_database {
	my ($db_file) = @_;

	# check if db exists
	my $new_db = 1;
	$new_db = 0 if (-e $db_file);

	# open database
	my $driver   = "SQLite";
	my $dsn = "DBI:$driver:$db_file";
	my $userid = "";
	my $password = "";
	my $dbh = DBI->connect($dsn, $userid, $password, { RaiseError => 1 })
		or die $DBI::errstr;

	if ($new_db) {
		# create table
		VTScan::create_table($dbh);
	}
	return $dbh;
}


# exit status: 0:clean; 1:exploit; 2:corrupted
sub check_file($;@) {

	# include configuration
	require "$config_file";

	my($fn) = @_;  # file name to be checked
	#my_log("called for $fn.");

	# check MIME type and file size
	my $file_size = -s $fn;
	my $magic = File::LibMagic->new;
	my $mime_type = $magic->checktype_filename($fn);
	$mime_type =~ s/;.*//;  # cut off character info
	my $exclude = ($file_size < $min_file_size
		|| (($#scan_only_files > -1) && !( grep { $mime_type =~ /$_/ } @scan_only_files ))
		|| (($#dont_scan_files > -1) && ( grep { $mime_type =~ /$_/ } @dont_scan_files )));
	my_log("called for $fn $mime_type size=$file_size".($exclude ? " EXCLUDED FROM SCAN" : ""));
	return @ret_ok if $exclude;

	# abort, if file vanished somehow
	die "File $fn vanished." unless defined($file_size);

	# calculate SHA1 key
	my $fh;
	die ("cannot open $fn") unless (open $fh, $fn);
	my $sha1 = Digest::SHA->new(1);
	$sha1->addfile($fh);
	my $sha1_key = $sha1->hexdigest;
	close $fh;

	# log file info
	my_log("checking $fn SHA1=$sha1_key");

	# check sha1 key in db
	my $vt_scan;
	my $curr_time = time();
	my $dbh;
	if (defined($db_file)) {

		# open database
		$dbh = open_database($db_file);

		# fetch record
		my $stmt = qq(SELECT * FROM vt_scan WHERE hash='$sha1_key');
		my $sth = $dbh->prepare( $stmt );
		my $rv = $sth->execute() or die $DBI::errstr;
		my @record = $sth->fetchrow_array();

		if ($#record > -1) {

			# record found
			$vt_scan = new VTScan(@record);
			if ($vt_scan->{tstamp} > $curr_time - $rescan_after_hours*3600) {
				my_log("returning database result for $sha1_key tstamp=".$vt_scan->{tstamp}." hits=".$vt_scan->{hits}." ".$vt_scan->{details});
				return ($vt_scan->{hits} >= $threshold ? 1 : 0, $vt_scan->{details});
			}
		}
	}

	# check file with virus total
	my @result = @ret_ok;
	my $ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 1 });
	my $response = $ua->post($url, ['apikey' => $api_key, 'resource' => $sha1_key]);
	die ("VT call failes") unless ($response->is_success);
	my $details = $response->content;
	my $json = JSON->new->allow_nonref;
	my $decjson = $json->decode($details);
	my $hits = ($decjson->{positives}) ? $decjson->{positives} : 0;
	my_log("returning result from virus-total: hits=$hits");

	# build result if hits were found
	if ($decjson->{"response_code"} > 0 && $hits > 0) {

		# virus: traverse scans and collect names of virus for scanners that detected a virus
		my $scans = $decjson->{scans};


#TODO


		my $rtext = $decjson->{scans}->{(keys(%$scans))[0]}->{result};
		if ($hits >= $threshold) {
			@result = (1, $rtext);
			my_log("found malware: hits=$hits >= $threshold $rtext");
		} else {
			my_log("found hits: hits=$hits < $threshold $rtext");
		}
	}

	if (defined($db_file)) {

		my $msg = "database record SHA1=$sha1_key hits=$hits result=".$result[0]." ".$result[1];

		# update / insert result record
		if (defined($vt_scan)) {
			# update record
			$vt_scan->{filename} = $fn;
			$vt_scan->{tstamp} = $curr_time;
			$vt_scan->{hits} = $hits;
			$vt_scan->{rcode} = $result[0];
			$vt_scan->{details} = $result[1];
			$vt_scan->update($dbh);
			my_log("updated $msg");
		}
		else {
			# insert record
			$vt_scan = new VTScan(($sha1_key,$fn,$curr_time,$hits,@result));
			$vt_scan->insert($dbh);
			my_log("inserted $msg");
		}

	}
	@result;
}

1;
