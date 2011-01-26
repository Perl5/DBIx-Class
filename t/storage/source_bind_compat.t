use strict;
use warnings;

use Test::More;
use Test::Warn;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

{
  package DBICTest::Legacy::Storage;
  use base 'DBIx::Class::Storage::DBI::SQLite';

  use Data::Dumper::Concise;

  sub source_bind_attributes { return {} }
}


my $schema = DBICTest::Schema->clone;
$schema->storage_type('DBICTest::Legacy::Storage');
$schema->connection('dbi:SQLite::memory:');

$schema->storage->dbh_do( sub { $_[1]->do(<<'EOS') } );
CREATE TABLE artist (
  artistid INTEGER PRIMARY KEY NOT NULL,
  name varchar(100),
  rank integer NOT NULL DEFAULT 13,
  charfield char(10)
)
EOS

my $legacy = sub { $schema->resultset('Artist')->search({ name => 'foo'})->next };
if (DBIx::Class->VERSION >= 0.09) {
  &throws_ok(
    $legacy,
    qr/XXXXXXXXX not sure what error to put here yet XXXXXXXXXXXXXXX/,
    'deprecated use of source_bind_attributes throws',
  );
}
else {
  &warnings_exist (
    $legacy,
    qr/\QThe source_bind_attributes() override in DBICTest::Legacy::Storage relies on a deprecated codepath/,
    'Warning issued during invocation of legacy storage codepath',
  );
}

done_testing;
