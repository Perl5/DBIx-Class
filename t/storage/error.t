use strict;
use warnings;

use Test::More;
use Test::Warn;
use Test::Exception;

use lib qw(t/lib);
use_ok( 'DBICTest' );
use_ok( 'DBICTest::Schema' );

my $schema = DBICTest->init_schema;

warnings_are ( sub {
  throws_ok (
    sub {
      $schema->resultset('CD')->create({ title => 'vacation in antarctica' })
    },
    qr/DBI Exception.+constraint failed.+cd\.artist.+NULL/s
  );  # as opposed to some other error
}, [], 'No warnings besides exception' );

my $dbh = $schema->storage->dbh;

throws_ok (
  sub {
    $dbh->do ('INSERT INTO nonexistent_table VALUES (1)')
  },
  qr/DBI Exception.+no such table.+nonexistent_table/s,
  'DBI exceptions properly handled by dbic-installed callback'
);

# This usage is a bit unusual but it was actually seen in the wild
# destruction of everything except the $dbh should use the proper
# exception fallback:

{
  undef ($schema);
  throws_ok (
    sub {
      $dbh->do ('INSERT INTO nonexistent_table VALUES (1)')
    },
    qr/DBI Exception.+unhandled by DBIC.+no such table.+nonexistent_table/s,
    'callback works after $schema is gone'
  );
}

done_testing;
