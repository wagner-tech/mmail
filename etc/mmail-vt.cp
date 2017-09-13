#!/bin/bash
set -e

base=$1

mkdir -p $base/usr/lib/python2.7/
cp -a src/mmail/perl/amavis_vt.pm $base/usr/lib/python2.7/

