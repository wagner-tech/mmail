#!/bin/bash
set -e

base=$1

mkdir -p $base/usr/lib/python2.7/
cp -a src/mmail/perl/amavis_vt.pm $base/usr/lib/python2.7/

# copy man page
mkdir -p $base/usr/share/man/man8
gzip -c src/mmail/etc/mmail-vt.8 >$base/usr/share/man/man8/mmail-vt.8.gz

