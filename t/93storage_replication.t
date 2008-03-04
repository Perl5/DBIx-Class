use strict;
use warnings;
use lib qw(t/lib);

use File::Copy;

use DBICTest;

use Test::More;
eval {use DBD::Multi};
plan skip_all => 'No DBD::Multi' if ($@);

plan tests => 3;

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

my $new_artist1 = $schema->resultset('Artist')->find(4);

isa_ok ($new_artist1, 'DBICTest::Artist');

# reconnect
my $schema2 = $schema->connect( [
				 [ $dsn1, '', '', { AutoCommit => 1 } ],
				 [ $dsn2, '', '', { priority => 10 } ],
				 [ $dsn3, '', '', { priority => 10 } ]
				]
			      );

# try and read (should fail)
eval { my $new_artist2 = $schema2->resultset('Artist')->find(4); };
ok($@, 'read after disconnect fails because it uses slave 1 which we have neglected to "replicate" yet');

# try and read (should succede after faked synchronisation)
copy($db_file1, $db_file2);
$schema2 = $schema->connect( [
			      [ $dsn1, '', '', { AutoCommit => 1 } ],
			      [ $dsn2, '', '', { priority => 10 } ],
			      [ $dsn3, '', '', { priority => 10 } ]
			     ]
			   );
my $new_artist3 = $schema2->resultset('Artist')->find(4);
isa_ok ($new_artist3, 'DBICTest::Artist');

unlink $db_file2;
