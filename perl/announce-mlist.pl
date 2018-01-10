#!/usr/bin/perl

use IO::Socket::UNIX;
use Cwd qw();

# Configuration
our $SOCK_PATH = "/var/run/mlist.sock";

my $usage = "$0 <list-name> <permission>\n <permission>: all|list|<.perm>";

# check command line
die $usage if ($#ARGV < 1);
my ($list, $perm) = @ARGV;

# check list name
die "list name must end with .mlist" unless $list =~ /.*\.mlist/;
die "list not existing" unless -f $list;

# check permission
die "invalid permission expression" unless
	$perm eq "all"
	|| $perm eq "list"
	|| -f $perm;

my $client = IO::Socket::UNIX->new(
	Type => SOCK_STREAM,
	Peer => $SOCK_PATH,
);

die "Can't create socket: $!" unless $client;

my $cwd = Cwd::cwd();

$client->send("A,$cwd,$list,$perm\n");
    
chomp (my $ans = <$client>);

die "mlistd: $ans" unless $ans eq "0";

