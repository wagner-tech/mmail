#!/bin/bash
set -e

base=$1

# copy mailgate (engrypter)
mkdir -p $base/etc
cp src/mmail/etc/gpg-mailgate.conf $base/etc/gpg-mailgate.conf

mkdir -p $base/usr/local/bin/
cp src/gpg-mailgate/gpg-mailgate.py $base/usr/local/bin/

mkdir -p $base/usr/lib/python2.7/
cp -a src/gpg-mailgate/GnuPG $base/usr/lib/python2.7/

# copy postfix config
mkdir -p $base/etc/postfix/
cp -r src/mmail/etc/mmail $base/etc/postfix
#mv $base/etc/postfix/mmail/ma*.cf.proto $base/etc/postfix

# create postfix directories
# -> über postmulti abbilden
#mkdir -p $base/etc/postfix/free_pass
#mkdir -p $base/var/mail/free_pass
#mkdir -p $base/var/cache/free_pass
#mkdir -p $base/etc/postfix/tls_smtp
#mkdir -p $base/var/mail/tls_smtp
#mkdir -p $base/var/cache/tls_smtp

# copy deamon + common stuff
mkdir -p $base/usr/share/perl5
cp src/mmail/perl/mlistd.pl $base/usr/local/bin/mlistd
cp src/mmail/perl/mGPG.pm $base/usr/share/perl5

# copy admin scripts
mkdir -p $base/usr/sbin
cp src/mmail/sh/mmail $base/usr/sbin
mkdir -p $base/etc/init.d
cp src/mmail/sh/decryptd $base/etc/init.d
cp src/mmail/sh/mlistd $base/etc/init.d

# copy man page
mkdir -p $base/usr/share/man/man8
gzip -c src/mmail/etc/mmail.8 >$base/usr/share/man/man8/mmail.8.gz

# copy mlist scripts & deamon
mkdir -p $base/usr/bin
cp src/mmail/perl/announce-mlist.pl $base/usr/bin/announce-mlist
cp src/mmail/perl/update-mlist.pl $base/usr/bin/update-mlist

