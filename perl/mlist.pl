#!/usr/bin/perl
use strict;

use mMail;

my $usage = "$0 COMMAND [<list-name> <permission>]\n COMMAND: list announce update info get delete\n <permission>: all|list|<.perm>";

# check command line
die $usage if ($#ARGV < 0);
my $command = shift;

# check installation
my $rc = system('export PATH="/usr/sbin/:$PATH"; mmail list >/dev/null');
die "mlist service not properly installed. See 'mmail list'." unless $rc eq 0;
my $mlist_status = `export PATH="/usr/sbin/:\$PATH"; mmail list |grep mlist`;
chomp $mlist_status;
die "mlist service not activated. See 'man mlist'." unless substr($mlist_status, -1) eq 1;

my $ret = 0;
if ($command eq "announce") {
	$ret = mMail::announce(@ARGV);
}
elsif ($command eq "list") {
	# fetch lists
	my @lists = mMail::list();
	foreach my $list (@lists) {
		print "List: $list->{'name'}   Access: $list->{'permit'}\n";
	} 
}
elsif ($command eq "update") {
	$ret = mMail::update();
}
elsif ($command eq "info") {
	my ($list_loc, @permit) = mMail::info(@ARGV);
	my $permit_type = shift(@permit);
	print ("List is on location: $list_loc\n");
	print ("List has permission:\n");
	if ($permit_type eq "all") {
		print ("  Open list access: Everyone can use this list.\n");
	}
	elsif ($permit_type eq "list") {
		print ("  Restricted list access: Only list members can use this list.\n");
	}
	else {
		print ("  Restricted list access: List can be used by:\n");
		my $out = join("\n", @permit);
		print $out;
	}
}
elsif ($command eq "get") {
	my (@members) = mMail::get(@ARGV);
	print ("List members are:\n");
	my $out = join("\n", @members);
	print $out;
}
elsif ($command eq "delete") {
	my $ret = mMail::delete(@ARGV);
	die "Deletion failed: $ret" unless $ret == 0;
	print ("List deleted.\n");
}
else {
	die "unnown command: $command";
}
die "failed: rc: $ret" unless ($ret == 0);
