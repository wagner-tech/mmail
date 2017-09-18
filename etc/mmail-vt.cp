#!/bin/bash
set -e

base=$1

# copy perl modul
mkdir -p $base/usr/share/perl5/
cp src/mmail/perl/amavis_vt.pm $base/usr/share/perl5/

# copy configutarion
cp src/mmail/perl/amavis_vt.cf $base/etc/

# copy man page
mkdir -p $base/usr/share/man/man8
gzip -c src/mmail/etc/mmail-vt.8 >$base/usr/share/man/man8/mmail-vt.8.gz

# create db dir
mkdir -p $base/var/lib/mmail/
