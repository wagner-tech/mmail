#!/usr/bin/perl -w

use Sys::Syslog qw(:standard :macros);
use Net::SMTP;

use strict;

# define configuration
our $PATH = "/home/mmail";
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

=cut
"""
# Read configuration from /etc/gpg-mailgate.conf
_cfg = RawConfigParser()
_cfg.read('/etc/gpg-mailgate.conf')
cfg = dict()
for sect in _cfg.sections():
	cfg[sect] = dict()
	for (name, value) in _cfg.items(sect):
		cfg[sect][name] = value

def log(msg):
	if cfg.has_key('logging') and cfg['logging'].has_key('file'):
		if cfg['logging']['file'] == "syslog":
			syslog.syslog(syslog.LOG_INFO | syslog.LOG_MAIL, msg)
		else:
			logfile = open(cfg['logging']['file'], 'a')
			logfile.write(msg + "\n")
			logfile.close()

verbose=cfg.has_key('logging') and cfg['logging'].has_key('verbose') and cfg['logging']['verbose'] == 'yes'

# Read e-mail from stdin
raw = sys.stdin.read()
raw_message = email.message_from_string( raw )
from_addr = raw_message['From']
to_addrs = sys.argv[1:]

def send_msg( message, recipients = None ):
	if recipients == None:
		recipients = to_addrs
	log("Sending email to: <%s>" % '> <'.join( recipients ))
	relay = (cfg['relay']['host'], int(cfg['relay']['port']))
	smtp = smtplib.SMTP(relay[0], relay[1])
	smtp.sendmail( from_addr, recipients, message.as_string() )

def encrypt_payload( payload, gpg_to_cmdline ):
	raw_payload = payload.get_payload(decode=True)
	if "-----BEGIN PGP MESSAGE-----" in raw_payload and "-----END PGP MESSAGE-----" in raw_payload:
		return payload
	gpg = GnuPG.GPGEncryptor( cfg['gpg']['keyhome'], gpg_to_cmdline, payload.get_content_charset() )
	gpg.update( raw_payload )
	payload.set_payload( gpg.encrypt() )
	
	isAttachment = payload.get_param( 'attachment', None, 'Content-Disposition' ) is not None
	
	if isAttachment:
		filename = payload.get_filename()
	
		if filename:
			pgpFilename = filename + ".pgp"
			
			if payload.get('Content-Disposition') is not None:
				payload.set_param( 'filename', pgpFilename, 'Content-Disposition' )
			if payload.get('Content-Type') is not None:
				if payload.get_param( 'name' ) is not None:
					payload.set_param( 'name', pgpFilename )

	if payload.get('Content-Transfer-Encoding') is not None:
		payload.replace_header( 'Content-Transfer-Encoding', "7bit" )

	return payload

def encrypt_all_payloads( message, gpg_to_cmdline ):
	encrypted_payloads = list()
	if type( message.get_payload() ) == str:
		return encrypt_payload( message, gpg_to_cmdline ).get_payload()
	for payload in message.get_payload():
		if( type( payload.get_payload() ) == list ):
			encrypted_payloads.extend( encrypt_all_payloads( payload, gpg_to_cmdline ) )
		else:
			encrypted_payloads.append( encrypt_payload( payload, gpg_to_cmdline ) )
	return encrypted_payloads

def get_msg( message ):
	if not message.is_multipart():
		return message.get_payload()
	return '\n\n'.join( [str(m) for m in message.get_payload()] )

keys = GnuPG.public_keys( cfg['gpg']['keyhome'] )
gpg_to = list()
ungpg_to = list()

for to in to_addrs:
	if to in keys and not ( cfg['default'].has_key('keymap_only') and cfg['default']['keymap_only'] == 'yes'  ):
		gpg_to.append( (to, to) )
	elif cfg.has_key('keymap') and cfg['keymap'].has_key(to):
		gpg_to.append( (to, cfg['keymap'][to]) )
	else:
		if verbose:
			log("Recipient (%s) not in domain list." % to)
		ungpg_to.append(to)

if gpg_to == list():
	if cfg['default'].has_key('add_header') and cfg['default']['add_header'] == 'yes':
		raw_message['X-GPG-Mailgate'] = 'Not encrypted, public key not found'
	if verbose:
		log("No encrypted recipients.")
	send_msg( raw_message )
	exit()

if ungpg_to != list():
	send_msg( raw_message, ungpg_to )

log("Encrypting email to: %s" % ' '.join( map(lambda x: x[0], gpg_to) ))

if cfg['default'].has_key('add_header') and cfg['default']['add_header'] == 'yes':
	raw_message['X-GPG-Mailgate'] = 'Encrypted by GPG Mailgate'

gpg_to_cmdline = list()
gpg_to_smtp = list()
for rcpt in gpg_to:
	gpg_to_smtp.append(rcpt[0])
	gpg_to_cmdline.extend(rcpt[1].split(','))

encrypted_payloads = encrypt_all_payloads( raw_message, gpg_to_cmdline )
raw_message.set_payload( encrypted_payloads )

send_msg( raw_message, gpg_to_smtp )
"""

