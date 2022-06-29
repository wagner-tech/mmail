#!/usr/bin/perl -w

use Sys::Syslog qw(:standard :macros);
use Net::SMTP;
use Email::Simple;
use Email::MIME;

use mMail;

use strict;

# define configuration
our $PATH = "/var/mmail";
our $FREEPASS = "127.0.0.1:10025";
our $TEXTFOOTER = "\n\n---\nmlist service provided by WagnerTech UG (www.wagnertech.de)\n";
our $HTMLFOOTER = '<hl><p>mlist service provided by <a href="http://wagnertech.de">WagnerTech UG</a></p>'."\n";
our $MAXMAILSIZE = 1000000;
our $SERVICE_SENDER = 'do-not-reply@wagnertech.de';

# define individual list configuration
our $SENDER = ""; # envelope data
our $SUBJECT_PREFIX = "";
our $FROM = "";
our $REPLY_TO = "";

require "/etc/mlist_check.cf";

sub log {
	my ($msg) = @_;
	syslog("info|mail", $msg);
}

sub send_list
{
	my $sender = shift;
	my $address = shift;

	die("5.5.4: GET is only allowed with one To: address") if (scalar @_ > 1);
	
	my $list = mMail::list_base_name($address);
	
	my $body = "\n\n$list has following members: \n\n";
	my @members = mMail::get($list);
	$body .= join("\n", @members);

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
sub send_bounce_mail {
	my $sender = shift;
	my $text = shift;
	
	my $email = Email::Simple->create(
	header => [
		From    => '<>',
		To      => $sender,
		Subject => 'Undelivered Mail Returned to Sender',
	],
	body => $text
	);

	# send mail back to sender
	my $smtp = Net::SMTP->new("$FREEPASS");
	$smtp->mail('<>');
	$smtp->recipient($sender);
	$smtp->data();
	$smtp->datasend($email->as_string);
	$smtp->dataend();
	my $code=$smtp->code();
	return 1 if ($code != 250);
	$smtp->quit;
 	return 0;
}
sub sender_is_permitted
{
	my $sender = shift;
	my $address = shift;

	$sender =~ s/^<//;	
	$sender =~ s/>$//;
	my $list = mMail::list_base_name($address);
	
	my $file = "$PATH/$list.permit";
	
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

sub process_mail {
	my $sender = shift;
	my $to = shift;
	my $mobj = shift;

	# check config data for this mail
	my $list = mMail::list_base_name($to);
	my $file = "$PATH/$list.config";
	
	if (-f $file) {
		require "$file";
		if (length $REPLY_TO) {
			if ($REPLY_TO eq "SENDER") {
				$mobj->header_str_set("Reply-To" => $sender);
			}
			elsif ($REPLY_TO eq "FROM") {
				$mobj->header_str_set("Reply-To" => $mobj->header("From"));
			}
			else {
				$mobj->header_str_set("Reply-To" => $REPLY_TO);
			}
		}
		$sender = $SENDER if (length $SENDER);
		$mobj->header_str_set("Subject" => "$SUBJECT_PREFIX ".$mobj->header("Subject")) if (length $SUBJECT_PREFIX);
		$mobj->header_str_set("From" => $FROM) if (length $FROM);
	}
	
	# check mail footer
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
	}
	my $raw = $mobj->as_string;
	
	# forward mail
	my $smtp = Net::SMTP->new("$FREEPASS");
	$smtp->mail($sender);
	$smtp->recipient($to);
	$smtp->data();
	$smtp->datasend("$raw");
	$smtp->dataend();
	my $code=$smtp->code();
	if ($code != 250) {
		my $response=$smtp->message();
		return $response;
	}
	$smtp->quit;
	return 1;
}

# Read e-mail from stdin
my $raw;
while (<STDIN>) {
	$raw .= $_;
}
die("5.5.4: mail is bigger than $MAXMAILSIZE bytes!") if (length $raw > $MAXMAILSIZE);

my $sender = shift;
my @to_addrs = @ARGV;

# convert strange STRATO forward address
$sender =~ s/.*=.*=.*=(.*)=(.*)@.*/$2\@$1/;

# check if $sender is not the name of a list. If so, do nothing
exit 0 if (mMail::is_list($sender));

my @not_permitted_lists;
my @not_success_mails;
foreach my $to (@to_addrs) {
	if (! sender_is_permitted($sender, $to)) {
		push(@not_permitted_lists, $to);
	}
}

# remove not permitted lists
foreach my $npl (@not_permitted_lists) {
	@to_addrs = grep(!/$npl/, @to_addrs);
}

# examine mail with its mail parts
my $mobj = Email::MIME->new($raw);
if ($mobj->header("Subject") eq "GET") {
	exit send_list($sender, @to_addrs);
}

foreach my $to (@to_addrs) {
	$mobj = Email::MIME->new($raw);
	my $rc = process_mail($sender, $to, $mobj);
	push(@not_success_mails,$to) if (scalar($rc) != 1);
}

if (scalar(@not_permitted_lists)+scalar(@not_success_mails) > 0) {
	# send bounce mail
	my $text = "This is the mMail system.\n\n";
	$text .= "I'm sorry to have to inform you that your message could not\n";
	$text .= "be delivered to one or more recipients. It's attached below.\n\n";
	$text .= "For further assistance, please send mail to postmaster.\n\n";
	if (scalar(@not_permitted_lists) > 0) {
		$text .= "Sender $sender is not permitted to send to these lists:\n";
		$text .= join(",", @not_permitted_lists)."\n\n";
	} 
	if (scalar(@not_success_mails) > 0) {
		$text .= "The following adresses could not be reached:\n";
		$text .= join(",", @not_success_mails)."\n\n";
	} 
	my $rc = send_bounce_mail($sender, $text);
	die($text) if ($rc != 0);
}

exit 0;
