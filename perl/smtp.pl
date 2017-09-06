#!/usr/bin/perl

use Net::SMTP;

use strict;

my $usage = 'usage: echo "data" |smtp.pl <recipients>';

my $LINK = "localhost";

die "$usage" if ($#ARGV < 0);

my $name = $ENV{'USER'};
my $hostname = `hostname`;

my $smtp = Net::SMTP->new($LINK);
$smtp->mail("$name\@$hostname");
$smtp->recipient(@ARGV);
$smtp->data();
while (<STDIN>) {
	$smtp->datasend($_);
}
my $res = $smtp->dataend();

print $smtp->message();

die "Could not send mail" unless $res;
