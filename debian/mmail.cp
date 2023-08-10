#!/bin/bash
set -e

base=$1

# copy mailgate (engrypter)
mkdir -p $base/etc
cp etc/gpg-mailgate.conf $base/etc/gpg-mailgate.conf

mkdir -p $base/usr/local/bin/
#cp src/gpg-mailgate/gpg-mailgate.py $base/usr/local/bin/

mkdir -p $base/usr/lib/python2.7/
#cp -a src/gpg-mailgate/GnuPG $base/usr/lib/python2.7/

# create dir for content filter
mkdir -p $base/etc/postfix/mmail
cp etc/mmail/mlist.contfilt.regexp.proto $base/etc/postfix/mmail

# create postfix directories
# -> über postmulti abbilden
#mkdir -p $base/etc/postfix/free_pass
#mkdir -p $base/var/mail/free_pass
#mkdir -p $base/var/cache/free_pass
#mkdir -p $base/etc/postfix/tls_smtp
#mkdir -p $base/var/mail/tls_smtp
#mkdir -p $base/var/cache/tls_smtp

# copy common stuff
mkdir -p $base/usr/share/perl5
cp perl/mGPG.pm $base/usr/share/perl5

# copy admin scripts
mkdir -p $base/lib/systemd/system/
cp etc/mlistd.service $base/lib/systemd/system/
mkdir -p $base/usr/sbin
cp sh/mmail $base/usr/sbin

# copy man page
mkdir -p $base/usr/share/man/man1
mkdir -p $base/usr/share/man/man8
gzip -c doc/mmail.8 >$base/usr/share/man/man8/mmail.8.gz
gzip -c doc/mlist.1 >$base/usr/share/man/man1/mlist.1.gz

# copy doc
mkdir -p $base/usr/share/doc/mmail
cp LICENSE $base/usr/share/doc/mmail/copyright

# copy mlist scripts & deamon
mkdir -p $base/usr/bin
cp sh/announce-mlist $base/usr/bin/
cp sh/update-mlist $base/usr/bin/
cp perl/mlist.pl $base/usr/bin/mlist
mkdir -p $base/usr/share/perl5/
cp perl/mMail.pm $base/usr/share/perl5/
mkdir -p $base/usr/local/bin
mkdir -p $base/usr/sbin
mkdir -p $base/etc
cp perl/mlist_check.pl $base/usr/local/bin/
cp perl/mlist_check.cf $base/etc/
cp perl/mlistd.pl $base/usr/sbin/mlistd
mkdir -p $base/var/mmail


