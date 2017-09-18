use amavis_vt("./amavis_vt.cf");

$ret = amavis_vt::check_file("Hallo");
print ("check_file: ".$ret);
1;