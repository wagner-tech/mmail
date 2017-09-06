#!/usr/bin/perl


#############################################################################
# GnuPG Daemon
#   runs as SMTP Proxy
#   
#############################################################################
# Copyright 2016 by Michael Wagner
# WagnerTech UG, Munchen
# License: GNU License version 2
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
my $DOMAIN = "mmail";
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
  
  # check for mlist support
  my $listpattern = "\.mlist\@$DOMAIN";
  foreach my $r (@recipients) {
  	if ($r =~ /$listpattern/) {
		syslog("info","checking list access");
  		
  		# check, whether sender is permitteted to send to the list
  		return(0, 554, 'Error: sender not permitted to send to list') unless sender_is_permitted($sender, $r);
  	}
  }

  my $body=$$data;

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

  return(1, $code, "$response");
}




sub Daemon {
	openlog "mmail_listd", "pid", "mail";
	my @local_domains = qw(${LOCALDOMAINS});
	my $server = new IO::Socket::INET Listen => 1, LocalPort => $LISTPORT;
	if (!$server) { syslog(LOG_CRIT, "Cannot bind to $LISTPORT"); exit -1; }
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


openlog "gpgdecrypt", "pid", "mail";
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
syslog(LOG_INFO, "$0 now running with pid $pid");
closelog;
Daemon();
exit -1; # should never be reached

