#!/bin/bash
set -e

base=$1

# copy mailgate (engrypter)
mkdir -p $base/etc
cp src/mmail/etc/gpg-mailgate.conf $base/etc/gpg-mailgate.conf

mkdir -p $base/usr/local/bin/
#cp src/gpg-mailgate/gpg-mailgate.py $base/usr/local/bin/

mkdir -p $base/usr/lib/python2.7/
#cp -a src/gpg-mailgate/GnuPG $base/usr/lib/python2.7/

# copy postfix config
mkdir -p $base/etc/postfix/mmail
cp src/mmail/etc/mmail/mlist.contfilt.regexp.proto $base/etc/postfix/mmail

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
cp src/mmail/perl/mGPG.pm $base/usr/share/perl5

# copy admin scripts
mkdir -p $base/etc/systemd/system/
cp src/mmail/etc/mlistd.service $base/etc/systemd/system/
mkdir -p $base/usr/sbin
cp src/mmail/sh/mmail $base/usr/sbin

# copy man page
mkdir -p $base/usr/share/man/man1
mkdir -p $base/usr/share/man/man8
gzip -c src/mmail/doc/mmail.8 >$base/usr/share/man/man8/mmail.8.gz
gzip -c src/mmail/doc/announce-mlist.1 >$base/usr/share/man/man1/announce-mlist.1.gz
gzip -c src/mmail/doc/update-mlist.1 >$base/usr/share/man/man1/update-mlist.1.gz

# copy mlist scripts & deamon
mkdir -p $base/usr/bin
cp src/mmail/perl/announce-mlist.pl $base/usr/bin/announce-mlist
cp src/mmail/perl/update-mlist.pl $base/usr/bin/update-mlist
mkdir -p $base/usr/local/bin
mkdir -p $base/etc
cp src/mmail/perl/mlist_check.pl $base/usr/local/bin/
cp src/mmail/perl/mlist_check.cf $base/etc/
cp src/mmail/perl/mlistd.pl $base/usr/local/bin/mlistd
mkdir -p $base/var/mmail

