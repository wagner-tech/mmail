#!/usr/bin/perl

use Net::SMTP;

use strict;

my $usage = 'usage: echo "data" |smtp.pl [-s SENDER] <recipients>';

my $LINK = "localhost";

die "$usage" if ($#ARGV < 0);

my $name = $ENV{'USER'};
my $hostname = `hostname`;
my $sender = "$name\@$hostname";
if ($ARGV[0] eq "-s") {
	shift(@ARGV);	
	$sender = shift(@ARGV);	
}


my $smtp = Net::SMTP->new($LINK);
$smtp->mail($sender);
$smtp->recipient(@ARGV);
$smtp->data();
while (<STDIN>) {
	$smtp->datasend($_);
}
my $res = $smtp->dataend();

print $smtp->message();

die "Could not send mail" unless $res;
