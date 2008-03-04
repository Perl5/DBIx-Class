use strict;
use warnings;
use lib qw(t/lib);

use File::Copy;

use DBICTest;

use Test::More;
plan tests => 1;

my $schema = DBICTest->init_schema();

$schema->storage_type( '::DBI::Replication' );


my $db_file1 = "t/var/DBIxClass.db";
my $db_file2 = "t/var/DBIxClass_slave1.db";
my $db_file3 = "t/var/DBIxClass_slave2.db";
my $dsn1 = $ENV{"DBICTEST_DSN"} || "dbi:SQLite:${db_file1}";
my $dsn2 = $ENV{"DBICTEST_DSN2"} || "dbi:SQLite:${db_file2}";
my $dsn3 = $ENV{"DBICTEST_DSN3"} || "dbi:SQLite:${db_file3}";

$schema->connect( [
		   [ $dsn1, '', '', { AutoCommit => 1 } ],
		   [ $dsn2, '', '', { priority => 10 } ],
		   [ $dsn3, '', '', { priority => 10 } ]
		  ]
		);

$schema->populate('Artist', [
			     [ qw/artistid name/ ],
			     [ 4, 'Ozric Tentacles']
			    ]);

# try and read (should fail)
my $new_artist = $schema->resultset('Artist')->find(4);

warn "artist : $new_artist\n";

# try and read (should succede after faked synchronisation)
copy($db_file1, $db_file2);

unlink $db_file2;

ok(1,"These aren't the tests you're looking for");
