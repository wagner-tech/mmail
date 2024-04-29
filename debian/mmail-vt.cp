#!/bin/bash
set -e

base=$1

# copy perl modul
mkdir -p $base/usr/share/perl5/
cp perl/amavis_vt.pm $base/usr/share/perl5/
cp perl/VTScan.pm $base/usr/share/perl5/

# copy configutarion
mkdir -p $base/etc/
cp perl/amavis_vt.cf $base/etc/

# copy amavis configuration
mkdir -p $base/etc/amavis/conf.d/
cp etc/55-mmail_filter_mode $base/etc/amavis/conf.d/55-mmail_filter_mode.example
cp etc/56-mmail_scanners $base/etc/amavis/conf.d/56-mmail_scanners.example

# copy man page
mkdir -p $base/usr/share/man/man8
gzip -c doc/mmail-vt.8 >$base/usr/share/man/man8/mmail-vt.8.gz

# create db dir
mkdir -p $base/var/lib/mmail/

