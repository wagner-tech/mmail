#!/bin/bash
set -e

base=$1

# copy mailgate (engrypter)
mkdir -p $base/etc
cp src/mMail/etc/gpg-mailgate.conf $base/etc/gpg-mailgate.conf

mkdir -p $base/usr/local/bin/
cp src/gpg-mailgate/gpg-mailgate.py $base/usr/local/bin/

mkdir -p $base/usr/lib/python2.7/
cp -a src/gpg-mailgate/GnuPG $base/usr/lib/python2.7/

# copy postfix config
mkdir -p $base/etc/postfix/
cp -a src/mMail/etc/mmail $base/etc/postfix
cp src/mMail/etc/mmail.etc/mmail.contfilt.regexp $base/etc/postfix/mmail

# create postfix directories
mkdir -p $base/etc/postfix/free_pass
mkdir -p $base/var/mail/free_pass
mkdir -p $base/var/cache/free_pass
mkdir -p $base/etc/postfix/tls_smtp
mkdir -p $base/var/mail/tls_smtp
mkdir -p $base/var/cache/tls_smtp

# copy list handler + decrypter + common stuff
mkdir -p $base/usr/share/perl5
cp src/mMail/perl/*.pl $base/usr/local/bin/
cp src/mMail/perl/mGPG.pm $base/usr/share/perl5

# copy filter files to mmail home
mkdir -p $base/home/mmail/etc
cp src/mMail/etc/mmail.etc/* $base/home/mmail/etc

# copy admin scripts
mkdir -p $base/usr/sbin
cp src/mMail/sh/mmail $base/usr/sbin
mkdir -p $base/etc/init.d
cp src/mMail/sh/decryptd $base/etc/init.d

