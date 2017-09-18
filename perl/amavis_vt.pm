package amavis_vt;

use strict;
use warnings;

use File::MimeInfo;

# define module constants
our $default_config_file = "/etc/amavis_vt.cf";
our $ret_ok = 0;
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
	our @scan_only_files = ("jpeg", "exe");
	our $dont_scan_files = 1;
	our $rescan_after_hours = 10;
	
	# include configuration
	require "$config_file";
	
	my($fn) = @_;  # file name to be checked
	
	# check MIME type and file size
	my $mime_type = mimetype($fn);
	my $file_size = -s $fn;
	
	# abort, if file vanished somehow
	return $ret_error unless defined($file_size);

	return $ret_ok if $file_size < $min_file_size;
	return $ret_ok if (@scan_only_files && !( grep { $_ eq $mime_type} @scan_only_files ));
=cut
IF @scan_only_files AND $file_type !~ $scan_only_files THEN
 RETURN OK;
END IF;
IF $dont_scan_files AND $file_type ~ $dont_scan_files THEN
 RETURN OK;
END IF;
=cut
	return 0;
}

1;