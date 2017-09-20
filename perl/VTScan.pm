package VTScan;

sub new {
	my ($db_record) = @_;
	my %inst = (
		hash => $db_record[0],
		filename => $db_record[1],
		tstamp => $db_record[2],
		hits => $db_record[3],
		rcode => $db_record[4],
		details => $db_record[5]
	);
	bless(\%inst, "VTScan");	
	return \%inst;
}

sub create_table {
	my ($dbh) = @_;
	my $stmt = qq(CREATE TABLE vt_scan(hash VARCHAR(255) PRIMARY KEY, filename TEXT,
		tstamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP, hits INTEGER, rcode INTEGER,
		details TEXT););
	my $rv = $dbh->do( $stmt ) or die $DBI::errstr;;
}

sub insert {
	my ($self, $dbh) = @_;
	my $stmt = qq(INSERT INTO vt_scan VALUES('$self->hash','$self->filename',
		$self->tstamp, $self->hits, $self->rcode, '$self->details'));
	my $rv = $dbh->do($stmt) or die $DBI::errstr;
}

sub update {
	my ($self, $dbh) = @_;
	my $stmt = qq(UPDATE vt_scan SET filename='$self->filename',tstamp=$self->tstamp,
		hits=$self->hits,rcode=$self->rcode,details='$self->details' WHERE hash='$self->hash");
	my $rv = $dbh->do($stmt) or die $DBI::errstr;
}

1;