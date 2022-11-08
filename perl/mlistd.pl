#!/usr/bin/perl

use IO::Socket::UNIX;
use strict;

# Configuration
our $SOCK_PATH = "/var/run/mlist.sock";
our $USER_DIR = "/var/mmail";

sub add_list {
	my ($list_path,$perm) = @_; 
	# parse list_path
	my $list_dir = $list_path;
	$list_dir =~ s/[^\/]*$//;
	my $list = $list_path;
	$list =~ s/.*\///;
	$list =~ s/\.mlist$//;
	
	# append list name to /etc/aliases
	open my $handle, '<', "/etc/aliases";
	chomp(my @aliases = <$handle>);
	close $handle;
	@aliases = grep(!/$list(:|\.mlist)/, @aliases);
	push (@aliases, "$list: :include:$USER_DIR/$list.mlist");
	push (@aliases, "$list.mlist: :include:$USER_DIR/$list.mlist");
	open $handle, '>', "/etc/aliases";
	print $handle join("\n", @aliases);
	close $handle;
	
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
	return 0;
}

sub add_list_member {
	# parameter: name of list
	#            e-mail address
	# return code: 0 = success
	#              1 = already in list
	#              5 = parameter_missing
	#              6 = invalid list name
	#              7 = invalid email format
	
	return "5,parameter_missing" if $#_ < 0; 
	my $list  = shift;
	my $email = shift;
	return "6,invalid list name: $list" until (-f "$USER_DIR/$list.mlist");
	return "7,invalid email format: $email" until ($email =~ /.*@.*\..*/);
	
	open my $fh, "<", "$USER_DIR/$list.mlist";
	my @addresses = <$fh>;
	close $fh;
	return "1,e-mail exists" if grep /$email/i, @addresses;
	open $fh, ">>", "$USER_DIR/$list.mlist";
	print $fh "$email\n";
	close $fh;
	return 0;
}

sub process_request {
	my @params = split(/,/,shift);
	my $cmd = shift(@params);
	
	if ($cmd eq "A") {
		return add_list(@params);
	}
	elsif ($cmd eq "D") {
		# delete request
		my $list = shift(@params);
		unlink glob "$USER_DIR/$list.*";
	}
	elsif ($cmd eq "C") {
		# change list configuration
		my ($list,$name,$value) = @params;

		my $file = "$USER_DIR/$list.config";
		my @configs;
		my $handle;
		if (-f $file) {
			# config file exists
			open $handle, '<', $file;
			chomp(@configs = <$handle>);
			close $handle;
			
			# remove existing config
			@configs = grep(!/$name/,@configs);
		}
		push(@configs, "\$$name = '$value';") if (length $value);
		push(@configs, "1;") if (scalar @configs == 0); 
		open $handle, '>', "$file";
		print $handle join("\n", @configs);
		close $handle;
	}
	elsif ($cmd eq "V") {
		return add_list_member(@params);
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
		while(chomp (my $line = <$conn>)) {
			my $ret = 0;
		
			$ret = process_request($line) unless ($line eq "U");
			if ($ret == 0) {
				# update list
				$ret = system("newaliases");
			}
			print $conn "$ret\n";
		}
	}
}
