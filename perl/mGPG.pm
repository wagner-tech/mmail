#!/usr/bin/perl

package mGPG;

use Crypt::GPG;

sub new {
	my $gpg = new Crypt::GPG;
	$gpg->gpgbin('/usr/bin/gpg');
	bless { GPG => $gpg
	}, shift;
}

sub getSecKeyName {
	my $self = shift;
	my $email = shift;
	
	my @keydb = $self->{GPG}->keydb();
	foreach my $entry (@keydb) {
		if ($entry->{"Type"} eq "sec") {
			my $uids = $entry->{"UIDs"};
			foreach my $uid (@$uids) {
				my $testmail = $uid->{"UID"};
				$testmail =~ s/.*<(.*)>.*/<$1>/;
				return $entry->{"ID"} if ($testmail eq $email);
			}
		}	
	}
	return undef;
}

sub setSecKeyName {
	my $self = shift;
	my $email = shift;
	# returns: bool
	
	my $id = $self->getSecKeyName($email);
	return 0 unless defined($id);
	$self->{GPG}->secretkey($id);
	return 1;
}

sub decrypt {
	my $self = shift;
	my $enctext = shift;
	
	return $self->{GPG}->verify($enctext);
}

1;
