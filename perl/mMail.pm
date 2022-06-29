package mMail;

use strict;

use IO::Socket::UNIX;
use Cwd qw();

# Configuration
our $SOCK_PATH = "/var/run/mlist.sock";
our $USER_DIR = "/var/mmail";

sub list_base_name {
	my $list = shift;

	$list =~ s/@.*//;
	$list =~ s/\.mlist$//;
	$list =~ s/^<//;
	
	return $list;
}
sub announce {
	
	die "Parameter missing: mlist annouce LIST PERM" if $#_ < 1; 
	my ($list, $perm) = @_;

	# check list name
	die "list '$list' not existing" unless -f $list;
	
	# check permission
	if ($perm eq "all" || $perm eq "list") {
		; # everything fine 
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
	
	return $ans;
}

sub update {
	my $client = IO::Socket::UNIX->new(
		Type => SOCK_STREAM,
		Peer => $SOCK_PATH,
	);
	
	die "Can't create socket: $!" unless $client;
	
	$client->send("U\n");
	    
	chomp (my $ans = <$client>);
	return $ans;
}
sub is_list {
	# Parameter: list name or address
	my $list = list_base_name(shift);
	return 1 if (-f "$USER_DIR/$list.mlist");
	return 0;
	
}
sub get_permit_type {
	my $list = shift;
	return "LIST_ERROR" until (-f "$USER_DIR/$list.mlist");
	
	if (-l "$USER_DIR/$list.permit") {
		# list or permit
		my $permit = readlink "$USER_DIR/$list.permit";
		return "list" if ($permit eq "$USER_DIR/$list.mlist");
		return $permit;
	}
	return "all";
}
sub require_permit_type {
	my $list = shift;
	my $permit_type = get_permit_type($list);
	die "invalid list name: $list" if ($permit_type eq "LIST_ERROR");
	return $permit_type;
}
sub list {
	# result is an array of lists. Each element has an enty for 'name' and 'permit'
	opendir(VZ, $USER_DIR);
	my @files = readdir(VZ);
	my @lists = grep(/.*\.mlist$/, @files);
	my @result;
	foreach my $list (@lists) {
		$list =~ s/\.mlist$//;
		my $permit_type = get_permit_type($list);
		push(@result, {'name' => $list, 'permit' => "$permit_type"});
	}
	return @result;
}
sub info {
	# parameter: name of list
	# result is an array:
	#   - list location
	#   - permission type
	#   - list ref of emails, if type != all,list
	#   - list ref of configuration
	
	die "Paramerter missing: mlist info LIST" if $#_ < 0; 
	my $list = shift;
	die "invalid list name: $list" until (-f "$USER_DIR/$list.mlist");
	
	# read list location
	my $list_loc = readlink "$USER_DIR/$list.mlist";
	
	my $permit_type = require_permit_type($list);
	my @addresses;
	if ($permit_type eq 'list' or $permit_type eq 'all') {
		# do nothing
		;
	}
	else {
		# read permit file
		open (RD, $permit_type) or die "cannot open $permit_type";
		@addresses = <RD>;
		chomp (@addresses);
		close (RD);
	}
	
	my @config;
	if (-f "$USER_DIR/$list.config") {
		# add configuration to info
		open (RD, "$USER_DIR/$list.config") or die "cannot open $USER_DIR/$list.config";
		@config = <RD>;
		chomp (@config);
		@config = grep(!/^1;/,@config);
		close (RD);
		
	}
	return ($list_loc, $permit_type, \@addresses, \@config);
}
sub get {
	# parameter: name of list
	# result is an array with list members
	die "Paramerter missing: mlist get LIST" if $#_ < 0; 
	my $list = shift;
	die "invalid list name: $list" until (-f "$USER_DIR/$list.mlist");

	open FILE, "<", "$USER_DIR/$list.mlist";
	my @members = <FILE>;
	chomp @members;
	return @members;	
}
sub config {
	# parameter: list name, list of configuration entries
	die "Paramerter missing: mlist config LIST CONFIGS" if $#_ < 1;
	my $list = shift;
	$list =~ s/\.mlist$//;
	die "invalid list name: $list" until (-f "$USER_DIR/$list.mlist");

	my $client = IO::Socket::UNIX->new(
		Type => SOCK_STREAM,
		Peer => $SOCK_PATH,
	);
	
	die "Can't create socket: $!" unless $client;

	my $ans;
	my @valid_configs = qw(SENDER SUBJECT_PREFIX FROM REPLY_TO);
	while (my $config = shift) {
		if ($config =~ /=/) {
			# set value
			my @confarr = split("=", $config);
			die "Invalid config entry: $confarr[0]" unless grep(/$confarr[0]/, @valid_configs);
			$client->send("C,$list,$confarr[0],$confarr[1]\n");
		}
		else {
			# reset value
			$client->send("C,$list,$config\n");
		}
		chomp ($ans = <$client>);
		return $ans unless ($ans == 0);
	}
	return $ans;
}
sub delete {
	# parameter: name of list
	# result is an array with list members
	die "Paramerter missing: mlist delete LIST" if $#_ < 0; 
	my $list = shift;
	die "invalid list name: $list" until (-f "$USER_DIR/$list.mlist");

	my $client = IO::Socket::UNIX->new(
		Type => SOCK_STREAM,
		Peer => $SOCK_PATH,
	);
	
	die "Can't create socket: $!" unless $client;
	
	$client->send("D,$list\n");
	    
	chomp (my $ans = <$client>);
	
	return $ans;
}
1;
