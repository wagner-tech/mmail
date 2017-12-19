#!/usr/bin/perl

use IO::Socket::UNIX;

# Configuration
our $SOCK_PATH = "/var/run/mlist.sock";
unlink $SOCK_PATH if -e $SOCK_PATH;
umask(0000);
# define server:
#my $server = IO::Socket::UNIX->new(
#    Type => SOCK_STREAM,
#    Local => $SOCK_PATH,
#    Listen => 1,
#);
my $server = IO::Socket::UNIX->new(
    Type => SOCK_DGRAM,
    Local => $SOCK_PATH,
    Listen => 1,
);

die "Can't create socket: $!" unless $server;

#while (my $conn = $server->accept())
#{
#	while (my $line = <$conn>) {
#    	print("$line");# . "\n");
#	}
#}
my $msg;
while (1) {
	$server->recv($msg,64);
	print("$msg");
}