#!/usr/bin/perl

use IO::Socket::UNIX;

# Configuration
our $SOCK_PATH = "/var/run/mlist.sock";
our $USER_DIR = "/home/mmail";

unlink $SOCK_PATH if -e $SOCK_PATH;
umask(0000);
# define server:
my $server = IO::Socket::UNIX->new(
    Type => SOCK_STREAM,
    Local => $SOCK_PATH,
    Listen => 1,
);
#my $server = IO::Socket::UNIX->new(
#    Type => SOCK_DGRAM,
#    Local => $SOCK_PATH,
#    Listen => 1,
#);

die "Can't create socket: $!" unless $server;

while (my $conn = $server->accept())
{
#	while (my $line = <$conn>) {
#    	print("$line");# . "\n");
#	}
	my $line = <$conn>;
	my $ret = 0;
	
	if ($line eq "U") {
		
		# update list
		$ret = system("newaliases");
	}
	else {
		my ($cmd,$list,$perm) = split(/,/,$line);
		if ($cmd eq "A") {
			system("grep -v \"^$list\" /etc/aliases > /tmp/aliases");
			system("mv /tmp/aliases /etc/aliases");
			system("echo \"$list: :include:$USER_DIR/$list\" >> /etc/aliases" );
		}
		else {
			$ret = 1;
		}  
		
	}
	print $conn "$ret\n";
}
#my $msg;
#while (1) {
#	$server->recv($msg,64);
#	print("$msg");
#}