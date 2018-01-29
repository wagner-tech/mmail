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
if ($perm eq "all" || $perm eq "list") {
	; # everythinf fine 
}
elsif (-f $perm) {
	if (substr($perm,0,1) eq "/") {
		; # absolute path
	}
	else {
		my $cwd = Cwd::cwd();
		$perm = "$cwd/$perm";
	}
} 
else { 
	die "invalid permission expression";
}

my $client = IO::Socket::UNIX->new(
	Type => SOCK_STREAM,
	Peer => $SOCK_PATH,
);

die "Can't create socket: $!" unless $client;

# expand relative path
if (substr($list,0,1) eq "/") {
	; # absolute path
}
else {
	my $cwd = Cwd::cwd();
	$list = "$cwd/$list";
}

$client->send("A,$list,$perm\n");
    
chomp (my $ans = <$client>);

die "mlistd: $ans" unless $ans eq "0";

