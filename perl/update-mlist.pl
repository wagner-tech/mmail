#!/usr/bin/perl

use IO::Socket::UNIX;

# Configuration
our $SOCK_PATH = "/var/run/mlist.sock";

my $client = IO::Socket::UNIX->new(
	Type => SOCK_STREAM,
	Peer => $SOCK_PATH,
);

die "Can't create socket: $!" unless $client;

$client->send("U\n");
    
chomp (my $ans = <$client>);

die "mlistd: $ans" unless $ans eq "0";

