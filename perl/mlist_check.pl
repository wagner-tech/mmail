#!/usr/bin/perl -w

use Sys::Syslog qw(:standard :macros);
use Net::SMTP;

use strict;

# define configuration
our $PATH = "/var/mmail";
our $FREEPASS = "127.0.0.1:10025";

require "/etc/mlist_check.cf";

sub log {
	my ($msg) = @_;
	syslog(LOG_INFO | LOG_MAIL, $msg);
}

sub sender_is_permitted
{
	my $sender = shift;
	my $address = shift;

	$sender =~ s/^<//;	
	$sender =~ s/>$//;	
	my $list = $address;
	$list =~ s/@.*//;
	$list =~ s/^<//;
	
	my $file = "$PATH/$list";
	$file =~ s/mlist$/permit/;
	::log("checking $file");
	# no file means: list access open for everyone
	return 1 unless -l $file;
	::log("open $file");
	open FILE, "<", "$file";
	while (<FILE>) {
		::log("info","$_ : $sender");
		return 1 if ($_ =~ /$sender/);
	}
	return 0;
}

sub queue_message
{
  my($session, $data) = @_;

  my $sender = $session->get_sender();
  my @recipients = $session->get_recipients();

  return(0, 554, 'Error: no valid recipients') unless(@recipients);
  
  # check for mlist support
  my $listpattern = "";#\.mlist\@$DOMAIN";
  foreach my $r (@recipients) {
  	if ($r =~ /$listpattern/) {
		syslog("info","checking list access");
  		
  		# check, whether sender is permitteted to send to the list
  		return(0, 554, 'Error: sender not permitted to send to list') unless sender_is_permitted($sender, $r);
  	}
  }
  
  ::log("--------------mlist_check.pl-----------------");

  my $body=$$data;

  my $smtp = Net::SMTP->new("$FREEPASS");
  $smtp->mail($sender);
  $smtp->recipient(@recipients);
  $smtp->data();
  $smtp->datasend("$body");
  $smtp->dataend();
  my $response=$smtp->message();
  if ($response=~/^(.+)\r?\n(.+)$/ms) { $response="$2"; }
  my $code=$smtp->code();
  $smtp->quit;

  return(1, $code, "$response");
}


# Read e-mail from stdin
my $raw;
while (<STDIN>) {
	$raw .= $_;
}
my $sender = shift;
my @to_addrs = @ARGV;
::log("Mail from $sender to ".$to_addrs[0]);

foreach my $to (@to_addrs) {
	sender_is_permitted($sender, $to) || die("554: sender not permitted to send to list $to");
}
::log("mail ok");

# forward mail
my $smtp = Net::SMTP->new("$FREEPASS");
$smtp->mail($sender);
$smtp->recipient(@to_addrs);
$smtp->data();
$smtp->datasend("$raw");
$smtp->dataend();
my $response=$smtp->message();
if ($response=~/^(.+)\r?\n(.+)$/ms) { die($2); }
#my $code=$smtp->code();
$smtp->quit;

exit 0;

