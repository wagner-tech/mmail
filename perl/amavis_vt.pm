package amavis_vt;

use strict;
use warnings;

use DBI;
use Digest::SHA;
use File::MimeInfo;
use Sys::Syslog qw(:standard :macros);

# define module constants
our $default_config_file = "/etc/amavis_vt.cf";
our @ret_ok = (0, "Clean");
our $ret_virus = 1;
our $ret_error = 2;

# define config file var
our $config_file;

# set config file with module parameter
sub import {
    my ($package, $file) = @_;
    $file = $default_config_file unless ($file);
    $config_file = $file;
}


# exit status: 0:clean; 1:exploit; 2:corrupted
sub check_file($;@) {
	# define default values
	our $db_file = "/var/lib/mmail/amavis-vt.db";
	our $api_key = "";
	our $min_file_size = 100;
	our @scan_only_files = ();
	our @dont_scan_files = ();
	our $rescan_after_hours = 10;
	
	# include configuration
	require "$config_file";
	
	my($fn) = @_;  # file name to be checked
	
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
	my $must_update = 0;
	if (defined($db_file)) {
		
		# open database
		my $driver   = "SQLite"; 
		my $dsn = "DBI:$driver:dbname = $db_file";
		my $userid = "";
		my $password = "";
		my $dbh = DBI->connect($dsn, $userid, $password, { RaiseError => 1 }) 
		   or die $DBI::errstr;
		  
		# fetch record
		my $stmt = qq(SELECT * FROM vt_scan WHERE hash=$sha1_key);
		my $sth = $dbh->prepare( $stmt );
		my $rv = $sth->execute() or die $DBI::errstr;
		
		# check return code
		if(($rv < 0) && ($DBI::errstr =~ /table doesn''t exist/)) {
			
			# create table
			my $stmt = qq(CREATE TABLE vt_scan(hash VARCHAR(255) PRIMARY INDEX, filename TEXT,
				tstamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP, hits INTEGER, result TEXT,
				details TEXT););
			my $sth = $dbh->prepare( $stmt );
			my $rv = $sth->execute() or die $DBI::errstr;
		}
		elsif ($rv < 0) {
			die "could not fetch record: $DBI::errstr";
		}
		else {
			
			# record found
			
		}
}

while(my @row = $sth->fetchrow_array()) {
      print "ID = ". $row[0] . "\n";
      print "NAME = ". $row[1] ."\n";
      print "ADDRESS = ". $row[2] ."\n";
      print "SALARY =  ". $row[3] ."\n\n";
}
	}
	
=cut
IF $db_file THEN
  $must_update = false
  öffne SQLite $db_file (erzeugt Datei falls nicht vorhanden)
  Ermittle record für ermittelten Hash:
   SELECT * FROM vt_scan WHERE hash=<SHA1>
  IF error_code == <table doesn''t exist> THEN
   Erzeuge Tabelle:
    CREATE TABLE vt_scan(hash VARCHAR(255) PRIMARY INDEX, filename TEXT,
tstamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP, hits INTEGER, result TEXT,
details TEXT);
  ELSEIF record found THEN
    IF record.tstamp > CURRENT_TIMESTAMP - $rescan_after_hours*3600 THEN
     RETURN record.result
    ENDIF
    $must_update = true
  ENDIF  
ENDIF



=cut
	return (5, "Ende");
}

1;