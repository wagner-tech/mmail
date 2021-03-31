#!/usr/bin/perl -w

use Sys::Syslog qw(:standard :macros);
use Net::SMTP;
use Email::Simple;
use Email::MIME;

use strict;

# define configuration
our $PATH = "/var/mmail";
our $FREEPASS = "127.0.0.1:10025";
our $TEXTFOOTER = "\n\n---\nmlist service provided by WagnerTech UG (www.wagnertech.de)\n";
our $HTMLFOOTER = '<hr><p>mlist service provided by <a href="http://wagnertech.de">WagnerTech UG</a></p>'."\n";
our $MAXMAILSIZE = 1000000;
our $SERVICE_SENDER = 'do-not-reply@wagnertech.de';

require "/etc/mlist_check.cf";

sub log {
	my ($msg) = @_;
	syslog("info|mail", $msg);
}

sub send_list
{
	my $sender = shift;
	die("5.5.4: GET is only allowed with one To: address") if (scalar @_ > 1);
	
	my $list = shift;
	$list =~ s/@.*//;
	$list =~ s/^<//;
	
	my $body = "\n\n$list has following members: \n\n";
	open FILE, "<", "$PATH/$list";
	$body .= $_ while (<FILE>);

	my $email = Email::Simple->create(
	header => [
		From    => $SERVICE_SENDER,
		To      => $sender,
		Subject => 'Re: GET',
	],
	body => $body
	);

	# send mail back to sender
	my $smtp = Net::SMTP->new("$FREEPASS");
	$smtp->mail($SERVICE_SENDER);
	$smtp->recipient($sender);
	$smtp->data();
	$smtp->datasend($email->as_string);
	$smtp->dataend();
	my $code=$smtp->code();
	if ($code != 250) {
		my $response=$smtp->message();
		die($response);
	}
	$smtp->quit;
 	return 0;
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
	
	
	# no file means: list access open for everyone
	unless (-l $file) {
		::log("free list access to $list");
		return 1;
	}
	open FILE, "<", "$file";
	while (<FILE>) {
		if ($_ =~ /$sender/i) {
			::log("free list access for $sender to $list");
			return 1;
		}
	}
	return 0;
}

# Read e-mail from stdin
my $raw;
while (<STDIN>) {
	$raw .= $_;
}
die("5.5.4: mail is bigger than $MAXMAILSIZE") if (length $raw > $MAXMAILSIZE);

my $sender = shift;
my @to_addrs = @ARGV;

# convert strange STRATO forward address
$sender =~ s/.*=.*=.*=(.*)=(.*)@.*/$2\@$1/;

foreach my $to (@to_addrs) {
	sender_is_permitted($sender, $to) || die("5.5.4: sender $sender not permitted to send to list $to");
}

# examine mail with its mail parts
my $mobj = Email::MIME->new($raw);
if ($mobj->header("Subject") eq "GET") {
	exit send_list($sender, @to_addrs);
}

if (length $TEXTFOOTER) {
	$mobj->walk_parts(sub {
	    my ($part) = @_;
	    return if $part->subparts; # multipart
	 
	 	my $ct = $part->content_type;
	    if ( $ct =~ m[text/plain]i and ! ($ct =~ m[name=]i)) {
	        my $body = $part->body;
	        $body .= $TEXTFOOTER;
	        $part->body_set( $body );
	    }
	    elsif ( $ct =~ m[text/html]i ) {
	        my $body = $part->body;
	    	$body =~ s!</body>!$HTMLFOOTER</body>!;
	        $part->body_set( $body );
	    }
	});
	$raw = $mobj->as_string;
}

# forward mail
my $smtp = Net::SMTP->new("$FREEPASS");
$smtp->mail($sender);
$smtp->recipient(@to_addrs);
$smtp->data();
$smtp->datasend("$raw");
$smtp->dataend();
my $code=$smtp->code();
if ($code != 250) {
	my $response=$smtp->message();
	die($response);
}
$smtp->quit;

exit 0;

