package mMail;

use IO::Socket::UNIX;
use Cwd qw();

# Configuration
our $SOCK_PATH = "/var/run/mlist.sock";
our $USER_DIR = "/var/mmail";

sub announce {
	
	die "Parameter missing: mlist annouce LIST PERM" if $#_ < 1; 
	my ($list, $perm) = @_;

	# check list name
	die "list name must end with .mlist" unless $list =~ /.*\.mlist/;
	die "list '$list' not existing" unless -f $list;
	
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
sub get_permit_type {
	my $list = shift;
	die "invalid list name: $list" until (-f "$USER_DIR/$list.mlist");
	
	if (-l "$USER_DIR/$list.permit") {
		# list or permit
		my $permit = readlink "$USER_DIR/$list.permit";
		return "list" if ($permit eq "$USER_DIR/$list.mlist");
		return $permit;
	}
	return "all";
}
sub list {
	# result is an array of lists. Each element has an enty for 'name' and 'permit'
	opendir(VZ, $USER_DIR);
	my @files = readdir(VZ);
	my @lists = grep(/.*mlist/, @files);
	my @result;
	foreach my $list (@lists) {
		$list =~ s/.mlist//;
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
	#   - list of emails, if type != all,list
	
	die "Paramerter missing: mlist info LIST" if $#_ < 0; 
	my $list = shift;
	die "invalid list name: $list" until (-f "$USER_DIR/$list.mlist");
	
	# read list location
	my $list_loc = readlink "$USER_DIR/$list.mlist";
	
	my $permit_type = get_permit_type($list);
	return ($list_loc, $permit_type) if ($permit_type eq 'list' or $permit_type eq 'all');
	
	open (RD, $permit_type) or die "cannot open $permit_type";
	my @addresses = <RD>;
	chomp (@addresses);
	return ($list_loc, $permit_type, @addresses);
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
