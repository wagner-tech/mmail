#!/usr/bin/perl
use strict;

use mMail;

my $usage = "$0 COMMAND [<list-name> <permission>]\n COMMAND: list announce update info get config delete\n <permission>: all|list|<.perm>";

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
	my ($list_loc, $permit_type, $permit, $config) = mMail::info(@ARGV);
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
		my $out = join("\n", @$permit);
		print "$out\n";
	}
	if (scalar @$config > 0) {
		# there is a list configuration
		print ("List configuration:\n");
		my $out = join("\n", @$config);
		print "$out\n";
	}
}
elsif ($command eq "get") {
	my (@members) = mMail::get(@ARGV);
	print ("List members are:\n");
	my $out = join("\n", @members);
	print $out;
}
elsif ($command eq "delete") {
	$ret = mMail::delete(@ARGV);
	die "Deletion failed: $ret" unless $ret == 0;
	print ("List deleted.\n");
}
elsif ($command eq "config") {
	$ret = mMail::config(@ARGV);
	die "Configuration failed: $ret" unless $ret == 0;
	print ("Configuration updated.\n");
}
elsif ($command eq "add") {
	$ret = mMail::add_list_member(@ARGV);
	die "List member add failed: $ret" if $ret > 1;
	if ($ret == 0) {
		print "List member added.\n";
	}
	elsif ($ret == 1) {
		print "List member already in list.\n";
		$ret = 0;
	}
	else {
		die "unexpected rc: $ret";
	}
}
else {
	die "unnown command: $command";
}
die "failed: rc: $ret" unless ($ret == 0);
