#!/usr/bin/perl


#############################################################################
# GnuPG Daemon
#   runs as SMTP Proxy
#   
#############################################################################
# This software is based on
#
# Copyright 2008 by Christian Felsing
# http://gpgdecrypter.sourceforge.net
# License: GNU License version 2
#
# Copyright 2016 my Michael Wagner
# WagnerTech UG, Munchen
#############################################################################


#############################################################################
# load configuration
#############################################################################
do "mmail.conf.pl";
# TODO: Das funktioniert nicht!
my $LISTPORT=31335;					# Postfix sends mail in first step to that port
my $DECRYPTPORT=31336;					# Postfix sends mail in first step to that port
my $ENCRYPTPORT=31337;					# Postfix sends mail in first step to that port
my $LOCALDOMAINS="taunusstein.net quake0.de";		# my domains 
my $DOMAIN = "wagnertech.de";
my $SMTPUPLINK="127.0.0.1:10025";			# gpgproxy sends mail to this SMTP server
							# may be Amavis
my $TMPDIR="/home/mmail/tmp";				# my tempdir, it must exists and
							# $USER must be able to write to that dir
my $USER="mmail";					# gpgproxy is running as this user
my $GROUP="mmail";					# gpgproxy is running as this group
							#   gpgproxy will not start as root
my $HOMEDIR="/home/mmail";				# where to find .gnupg dir
my $passphrase=`cat ${HOMEDIR}/key.txt`;		# Passphrase of private GnuPG key
my $MAXLEN=10240000;					# max size of msg.
my $PATH = "/home/mmail/etc";



#############################################################################
# no more to config
#############################################################################
use IO::Socket::INET;
use Net::Server::Mail::ESMTP; # extra dependency!
use MIME::Parser;
use mGPG;
use Net::SMTP;
use File::stat;
use POSIX;
use Sys::Syslog qw(:standard :macros);

use strict;


sub log {
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
	
	my $file = "$PATH/$list.permit";
	# no file means: list access open for everyone
	return 1 unless -f $file;
	open FILE, "<", "$file";
	while (<FILE>) {
		syslog("info","$_ : $sender");
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
  
  my $parser = MIME::Parser->new;
  $parser->output_dir("$TMPDIR");
  $parser->decode_bodies(0);
  my $entity=$parser->parse_data($$data);
  my $head = $entity->head;
  my $msgid=$head->get('Message-ID');
  if ( $entity->effective_type ne 'multipart/signed' and $entity->effective_type ne 'multipart/encrypted' ) {
    $parser->decode_bodies(1);
    $entity = $parser->parse_data($$data);
  }

  my $body = "default-text";
  my $mg = new mGPG;
  my $encrypted = ($$data =~ /PGP MESSAGE/);
  if ($encrypted) {
  	
		# encrypted messages must only address one recipient   	
		return(0, 555, 'Error: more than one recipient') if($#recipients > 0);
		my $recipient = $recipients[0];
  	
  	# define private key
  	my $priv_key_exists = $mg->setSecKeyName($recipient);
  	if ($priv_key_exists) {
  		my $decrypted_entity = $mg->decrypt($$data);
#	Das haut nicht hin :-)
#		$head->add('X-Decrypter:','wagnertech.de gpgdecrypter');
#		$head->add('To:','wagnertech.de gpgdecrypter');
		$body="X-Decrypter: wagnertech.de gpgdecrypter\nTo: $recipient\n$decrypted_entity";
		syslog("info", "$msgid : data successfully decrypted");
	} else {
		syslog("info", "$msgid : no private key found, passing it");
		$body=$$data;
	}
  } else {
		syslog("info", "$msgid : not encrypted, passing it");
		$body=$$data;
  }
  	
   
    



=cut
    my ($decrypted_entity, $result) = $mg->decrypt ( entity => $entity, passphrase => $passphrase );
    my $decryption_ok = $result->get_enc_ok;
    if ($decryption_ok) {
      syslog("info", "$msgid : data successfully decrypted");
      $body=$decrypted_entity->as_string;
    } else {
      my $stdout=$result->get_gpg_stdout;
      my $stderr=$result->get_gpg_stderr;
      my $error=$$stdout . " " . $$stderr;
      syslog("notice", "$msgid : cannot decrypt data, passing it");
      syslog("notice", "$msgid : $error");
      $body=$$data;
    }
  } else {
    syslog("info", "$msgid : not encrypted, passing it");
    $body=$$data;
  }
=cut
  my $smtp = Net::SMTP->new("${SMTPUPLINK}");
  $smtp->mail($sender);
  $smtp->recipient(@recipients);
  $smtp->data();
  $smtp->datasend("$body");
  $smtp->dataend();
  my $response=$smtp->message();
  if ($response=~/^(.+)\r?\n(.+)$/ms) { $response="$2"; }
  my $code=$smtp->code();
  $smtp->quit;
  $parser->filer->purge;

  return(1, $code, "$response");
}




sub Daemon {
	openlog "decrypt", "pid", "mail";
	my @local_domains = qw(${LOCALDOMAINS});
	my $server = new IO::Socket::INET Listen => 1, LocalPort => $DECRYPTPORT;
	if (!$server) { syslog(LOG_CRIT, "Cannot bind to $DECRYPTPORT"); exit -1; }
	my $conn;
	while($conn = $server->accept)
	{
		my $smtp = new Net::Server::Mail::ESMTP socket => $conn;
		# activate some extensions
		$smtp->register('Net::Server::Mail::ESMTP::8BITMIME');
		$smtp->register('Net::Server::Mail::ESMTP::PIPELINING');
		$smtp->register('Net::Server::Mail::ESMTP::XFORWARD');
		#$smtp->register('Net::Server::Mail::ESMTP::SIZE');
		#$smtp->set_size($MAXLEN);
		# rest of SMTP
		$smtp->set_callback(DATA => \&queue_message);
		$smtp->process();
		$conn->close()
	}
}


openlog "decryptd", "pid", "mail";
chdir '/home/gpguser';
my $uid=getpwnam ("$USER");
my $gid=getgrnam ("$GROUP");
POSIX::setgid($gid) || die "cannot set group to $GROUP\n\n";
POSIX::setuid($uid) || die "cannot set user to $USER\n\n";
if ($> == 0) { syslog(LOG_CRIT, "I am not running as user root"); exit -1; }
if ($) == 0) { syslog(LOG_CRIT, "I am not running as group root"); exit -1; }
$< = $>;
$( = $);
$ENV{"HOME"}="$HOMEDIR";
if (-d $TMPDIR && -w $TMPDIR && -r $TMPDIR && -x $TMPDIR) {
  syslog(LOG_INFO, "$TMPDIR exist and I have enough rights");
} else {
  print("$TMPDIR does not exists or is not accessible\n");
  exit -1;
}
syslog(LOG_INFO, "$0 now running as ${USER}:${GROUP}");
open STDIN, '/dev/null'   or die "Can't read /dev/null: $!";
open STDOUT, '>/dev/null' or die "Can't write to /dev/null: $!";
#open STDERR, '>/dev/null' or die "Can't write to /dev/null: $!";
defined(my $pid = fork)   or die "Can't fork: $!";
exit if $pid;
closelog;
Daemon();
exit -1; # should never be reached

