#!/usr/bin/perl

use IO::Socket::UNIX;
use strict;

# Configuration
our $SOCK_PATH = "/var/run/mlist.sock";
our $USER_DIR = "/var/mmail";

sub process_request {
	my ($cmd,$list_path,$perm) = split(/,/,shift);
	return "1,unknown command: $cmd" unless ($cmd eq "A");

	# parse list_path
	my $list_dir = $list_path;
	$list_dir =~ s/[^\/]*$//;
	my $list = $list_path;
	$list =~ s/.*\///;

	# TODO: ggf auf perl-File-Funktionen umstellen
	my $rc = system("grep -v \"^$list\" /etc/aliases > /tmp/aliases");
	return "$rc,grep -v failed" unless $rc == 0;
	$rc = system("mv /tmp/aliases /etc/aliases");
	return "$rc,mv failed" unless $rc == 0;
	$rc = system("echo \"$list: :include:$USER_DIR/$list\" >> /etc/aliases" );
	return "$rc,append failed" unless $rc == 0;

	$rc = system("ln -sf $list_path $USER_DIR/$list" );
	return "$rc,link failed" unless $rc == 0;

	my $perm_path = "$USER_DIR/$list";
	$perm_path =~ s/mlist$/permit/;
	unlink $perm_path if (-l $perm_path);
	if ($perm eq "all") {
		; # do nothing
	} elsif ($perm eq "list") {
		$rc = system("ln -s $USER_DIR/$list $perm_path");
		return "$rc,link list to perm failed" unless $rc == 0;
	} else {
		$rc = system("ln -s $perm $perm_path");
		return "$rc,link perm file failed" unless $rc == 0;
	}
	return 0;
}

# local test modus
my $command_line = shift(@ARGV);
if (defined $command_line) {
	print (process_request($command_line));
	exit;
}

unlink $SOCK_PATH if -e $SOCK_PATH;
umask(0000);
# define server:
my $server = IO::Socket::UNIX->new(
    Type => SOCK_STREAM,
    Local => $SOCK_PATH,
    Listen => 1,
);

die "Can't create socket: $!" unless $server;

while (1)
{
	if (my $conn = $server->accept()) {
		chomp (my $line = <$conn>);
		my $ret = 0;
	
		$ret = process_request($line) unless ($line eq "U");
		if ($ret == 0) {
			# update list
			$ret = system("newaliases");
		}
		print $conn "$ret\n";
	}
}
