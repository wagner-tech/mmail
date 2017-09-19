#!/usr/bin/perl

use amavis_vt("./amavis_vt.cf");

@ret = amavis_vt::check_file("../mMailTest/etc/MailVirus.txt");
print ("check_file: ".$ret[0].$ret[1]);
1;