#!/bin/bash
set -e

BUILD_DIR=~/build
mkdir -p $1/usr/lib/mlistc
cp $BUILD_DIR/csharp/mlistc/mlistc.exe $1/usr/lib/mlistc
cp $BUILD_DIR/csharp/mListDll/mlist.dll $1/usr/lib/mlistc
mkdir -p $1/usr/bin
cp csharp/bin/mlistc $1/usr/bin

