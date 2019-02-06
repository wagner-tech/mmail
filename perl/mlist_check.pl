#!/usr/bin/perl -w

use Sys::Syslog qw(:standard :macros);
use Net::SMTP;

use strict;

# define configuration
our $PATH = "/var/mmail";
our $FREEPASS = "127.0.0.1:10025";

require "/etc/mlist_check.cf";

sub log {
	my ($msg) = @_;
	syslog("info|mail", $msg);
}

sub sender_is_permitted
{
	my $sender = shift;
	my $address = shift;

	$sender =~ s/^<//;	
	$sender =~ s/>$//;	
	my $list = $address;
	$list =~ s/@.*//;
	$list =~ s/^<//;
	
	my $file = "$PATH/$list";
	$file =~ s/mlist$/permit/;
	
	
	# no file means: list access open for everyone
	unless (-l $file) {
		::log("free list access to $list");
		return 1;
	}
	open FILE, "<", "$file";
	while (<FILE>) {
		if ($_ =~ /$sender/) {
			::log("free list access for $sender to $list");
			return 1;
		}
	}
	return 0;
}

# Read e-mail from stdin
my $raw;
while (<STDIN>) {
	$raw .= $_;
}
my $sender = shift;
my @to_addrs = @ARGV;

foreach my $to (@to_addrs) {
	sender_is_permitted($sender, $to) || die("5.5.4: sender $sender not permitted to send to list $to");
}

# forward mail
my $smtp = Net::SMTP->new("$FREEPASS");
$smtp->mail($sender);
$smtp->recipient(@to_addrs);
$smtp->data();
$smtp->datasend("$raw");
$smtp->dataend();
my $code=$smtp->code();
if ($code != 250) {
	my $response=$smtp->message();
	die($response);
}
$smtp->quit;

exit 0;

