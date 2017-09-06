#!/usr/bin/perl

use strict;

# usage: commenter.pl <file> <tag> enbale|disable

# for "enable"
#TAG_+n# adds a '#' to the next n lines
#TAG_-n# removes a '#' in the next n lines
# for "disable" vice versa

die "Invalid parameter count." unless $#ARGV == 2;

my ($file, $tag, $op) = @ARGV;

open(DATEI, "<$file") || die "cannot read $file";

my @main_lines = <DATEI>;

close(DATEI);

open(DATEI, ">$file") || die "cannot write $file";

my $status = "search";
my $counter = 0;
my $count;
foreach(@main_lines) {
	if ($status eq "search") {
		if ($_ =~ /^#${tag}_/) {
			my $line = $_;
			$line =~ s/^#${tag}_//;
			my $first_char = substr($line, 0, 1);
			if (  ($first_char eq "+" && $op eq "enable")
			    ||($first_char eq "-" && $op eq "disable")) {
				$status = "remove";
			} else {
				$status = "add";
			}
			$count = $line;
			$count =~ s/^.//;
			$count =~ s/#.*//;
			$counter = 0;
		}
		print(DATEI $_);
	}
	elsif ($status eq "add") {
		my $line = $_;
		$line = "#$line" if (substr($line, 0, 1) ne "#");
		print (DATEI $line);
		$counter++;
		$status = "search" if ($counter == $count);
	}
	elsif ($status eq "remove") {
		my $line = $_;
		$line = substr($line, 1) if (substr($line, 0, 1) eq "#");
		print (DATEI $line);
		$counter++;
		$status = "search" if ($counter == $count);
	}
	else {
		die "invalid status";
	}
}
