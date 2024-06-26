package amavis_vt;

use strict;
use warnings;

use DBI;
use Digest::SHA;
use File::MimeInfo;
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
our $threshold = 5;
our @scan_only_files = ();
our @dont_scan_files = ();
our $rescan_after_hours = 10;
our $url='https://www.virustotal.com/vtapi/v2/file/report';

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
	syslog(LOG_INFO, "amavis_vt: called for $fn.");
	
	# check MIME type and file size
	my $mime_type = mimetype($fn);
	my $file_size = -s $fn;
	
	# abort, if file vanished somehow
	die "File $fn vanished." unless defined($file_size);

	return @ret_ok if $file_size < $min_file_size;
	return @ret_ok if (($#scan_only_files>-1) && !( grep { $_ eq $mime_type} @scan_only_files ));
	return @ret_ok if (($#dont_scan_files>-1) && ( grep { $_ eq $mime_type} @dont_scan_files ));
	syslog(LOG_INFO, "amavis_vt: checking $fn.");

	# calculate SHA1 key
	my $fh;
	die ("cannot open $fn") unless (open $fh, $fn);
	my $sha1 = Digest::SHA->new(1);
	$sha1->addfile($fh);
	my $sha1_key = $sha1->hexdigest;
	close $fh;

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
				syslog(LOG_INFO, "amavis_vt: returning result from database.");
				return ($vt_scan->{rcode}, $vt_scan->{details});
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
	syslog(LOG_INFO, "amavis_vt: returning result from virus-total.");
	
	# build result
	if ($decjson->{"response_code"} > 0 && $hits > $threshold) {
	  	
	  	# virus: extract text result of first hit
	  	my $scans = $decjson->{scans};
	  	my $rtext = $decjson->{scans}->{(keys(%$scans))[0]}->{result};
	  	@result = (1, $rtext);
	}

	if (defined($db_file)) {
		
		# update / insert result record
		if (defined($vt_scan)) {
			
			# update record
			$vt_scan->{filename} = $fn;
			$vt_scan->{tstamp} = $curr_time;
			$vt_scan->{hits} = $hits;
			$vt_scan->{rcode} = $result[0];
			$vt_scan->{details} = $result[1];
			$vt_scan->update($dbh);
		}
		else {
			# insert record
			$vt_scan = new VTScan(($sha1_key,$fn,$curr_time,$hits,@result));
			$vt_scan->insert($dbh);
		}
		
	}
	@result;
}

1;