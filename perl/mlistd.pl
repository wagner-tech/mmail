#!/usr/bin/perl

use IO::Socket::UNIX;
use strict;

# Configuration
our $SOCK_PATH = "/var/run/mlist.sock";
our $USER_DIR = "/var/mmail";

sub process_request {
	my ($cmd,$list_path,$perm) = split(/,/,shift);
	
	if ($cmd eq "A") {

		# parse list_path
		my $list_dir = $list_path;
		$list_dir =~ s/[^\/]*$//;
		my $list = $list_path;
		$list =~ s/.*\///;
		
		# append list name to /etc/aliases
		open my $handle, '<', "/etc/aliases";
		chomp(my @aliases = <$handle>);
		close $handle;
		unless (grep(/$list/, @aliases)) {
			push (@aliases, "$list: :include:$USER_DIR/$list.mlist");
			open $handle, '>', "/etc/aliases";
			print $handle join("\n", @aliases);
			close $handle;
		}
		
		# append list name to /etc/postfix/mmail/mlist.contfilt.regexp
		open CONTFILT, "/etc/postfix/mmail/mlist.contfilt.regexp";
		my @contfilt = <CONTFILT>;
		close CONTFILT;
		if (! grep (/$list@/, @contfilt)) {
			open CONTFILT, ">>/etc/postfix/mmail/mlist.contfilt.regexp";
			print CONTFILT "/$list@/ FILTER mlist_check:[127.0.0.1]";
			close CONTFILT;
		}
	
		my $rc = system("ln -sf $list_path $USER_DIR/$list.mlist" );
		return "$rc,link failed" unless $rc == 0;
	
		my $perm_path = "$USER_DIR/$list.permit";
		#$perm_path =~ s/mlist$/permit/;
		unlink $perm_path if (-l $perm_path);
		if ($perm eq "all") {
			; # do nothing
		} elsif ($perm eq "list") {
			$rc = system("ln -s $USER_DIR/$list.mlist $perm_path");
			return "$rc,link list to perm failed" unless $rc == 0;
		} else {
			$rc = system("ln -s $perm $perm_path");
			return "$rc,link perm file failed" unless $rc == 0;
		}
	}
	elsif ($cmd eq "D") {
		# delete request

		# get list name
		my $list = $list_path;
		$list =~ s/.*\///;
		$list =~ s/.mlist$//;
		
		unlink glob "$USER_DIR/$list.*";
	}
	else {
		return "1,unknown command: $cmd";
	}
	return 0;
}

# local test modus
my $command_line = shift(@ARGV);
if (defined $command_line) {
	print (process_request($command_line));
	exit;
}

unlink $SOCK_PATH if -e $SOCK_PATH;
umask(0000);
# define server:
my $server = IO::Socket::UNIX->new(
    Type => SOCK_STREAM,
    Local => $SOCK_PATH,
    Listen => 1,
);

die "Can't create socket: $!" unless $server;

while (1)
{
	if (my $conn = $server->accept()) {
		chomp (my $line = <$conn>);
		my $ret = 0;
	
		$ret = process_request($line) unless ($line eq "U");
		if ($ret == 0) {
			# update list
			$ret = system("newaliases");
		}
		print $conn "$ret\n";
	}
}
