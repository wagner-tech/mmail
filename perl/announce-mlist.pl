#!/usr/bin/perl

use IO::Socket::UNIX;

# Configuration
our $SOCK_PATH = "/var/run/mlist.sock";

my $client = IO::Socket::UNIX->new(
#	Type => SOCK_STREAM,
	Type => SOCK_DGRAM,
	Peer => $SOCK_PATH,
);

die "Can't create socket: $!" unless $client;

$client->send("Hallo\n");
    