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

throws_ok
  { $schema->storage->ensure_connected }
  qr/\Qstorage subclass DBICTest::Legacy::Storage provides (or inherits) the method source_bind_attributes()/,
  'deprecated use of source_bind_attributes throws',
;

done_testing;
