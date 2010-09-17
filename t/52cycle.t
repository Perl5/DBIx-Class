use strict;
use warnings;
use Test::More;

use lib qw(t/lib);

BEGIN {
  require DBIx::Class;
  plan skip_all => 'Test needs: ' . DBIx::Class::Optional::Dependencies->req_missing_for ('test_cycle')
    unless ( DBIx::Class::Optional::Dependencies->req_ok_for ('test_cycle') );
}

use DBICTest;
use DBICTest::Schema;
use Scalar::Util 'weaken';
use namespace::clean;

import Test::Memory::Cycle;

my $weak;

{
  my $s = $weak->{schema} = DBICTest->init_schema;
  ok ($s->storage->connected, 'we are connected');
  memory_cycle_ok($s, 'No cycles in schema');

  my $storage = $weak->{storage} = $s->storage;
  memory_cycle_ok($storage, 'No cycles in storage');

  my $rs = $weak->{resultset} = $s->resultset ('Artist');
  memory_cycle_ok($rs, 'No cycles in resultset');

  my $rsrc = $weak->{resultsource} = $rs->result_source;
  memory_cycle_ok($rsrc, 'No cycles in resultsource');

  my $row = $weak->{row} = $rs->first;
  memory_cycle_ok($row, 'No cycles in row');

  my $sqla = $weak->{sqla} = $s->storage->sql_maker;
  memory_cycle_ok($sqla, 'No cycles in SQL maker');

  my $dbh = $weak->{dbh} = $s->storage->_get_dbh;
  memory_cycle_ok($dbh, 'No cycles in DBI handle');

  for (@{$dbh->{ChildHandles}}) {
    $weak->{"$_"} = $_ if $_;
  }

  weaken $_ for values %$weak;
  memory_cycle_ok($weak, 'No cycles in weak object collection');
}

for (keys %$weak) {
  ok (! $weak->{$_}, "No $_ leaks");
}

done_testing;
