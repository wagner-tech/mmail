# mmail
WagnerTech Mail Utilities

## Features

### mlist
mmail mailling list support. See mmail(8)

### mmail-vt
virus total support for postfix. See mmail-vt(8)

## Getting Started

There are two possibilities to get this software: By installing the debian package from 
wagnertech.de or building the package yourself.

### Installing from package repositoy
Add to your package sources
```
deb http://wagnertech.de/debian/ stable main
```
Download und import the key:
```
wget http://wagnertech.de/debian/conf/wagnertech.key
sudo apt-key add wagnertech.key
```
Update and install:
```
sudo apt-get update
sudo apt-get install mmail
```
### Building package from sources
After cloning this repository
```
cd mmail/build
./start_build
./configure mmail <build_tag>
make
make deb
```
## Versions
0.1: mmail-vt

0.2: mlist

