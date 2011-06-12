use strict;
use warnings;

use Test::More;
use Test::Exception;
use Test::Warn;
use Config;

use lib qw(t/lib);
use DBICTest;

# savepoints test
{
  my $schema = DBICTest->init_schema(auto_savepoint => 1);

  my $ars = $schema->resultset('Artist');

  # test two-phase commit and inner transaction rollback from nested transactions
  $schema->txn_do(sub {
    $ars->create({ name => 'in_outer_transaction' });
    $schema->txn_do(sub {
      $ars->create({ name => 'in_inner_transaction' });
    });
    ok($ars->search({ name => 'in_inner_transaction' })->first,
      'commit from inner transaction visible in outer transaction');
    throws_ok {
      $schema->txn_do(sub {
        $ars->create({ name => 'in_inner_transaction_rolling_back' });
        die 'rolling back inner transaction';
      });
    } qr/rolling back inner transaction/, 'inner transaction rollback executed';
    $ars->create({ name => 'in_outer_transaction2' });
  });

  ok($ars->search({ name => 'in_outer_transaction' })->first,
    'commit from outer transaction');
  ok($ars->search({ name => 'in_outer_transaction2' })->first,
    'second commit from outer transaction');
  ok($ars->search({ name => 'in_inner_transaction' })->first,
    'commit from inner transaction');
  is $ars->search({ name => 'in_inner_transaction_rolling_back' })->first,
    undef,
    'rollback from inner transaction';
}

my $schema = DBICTest->init_schema();

# make sure the side-effects of RT#67581 do not result in data loss
my $row;
warnings_exist { $row = $schema->resultset('Artist')->create ({ name => 'alpha rank', rank => 'abc' }) }
  [qr/Non-numeric value supplied for column 'rank' despite the numeric datatype/],
  'proper warning on string insertion into an numeric column'
;
$row->discard_changes;
is ($row->rank, 'abc', 'proper rank inserted into database');

# and make sure we do not lose actual bigints
{
  package DBICTest::BigIntArtist;
  use base 'DBICTest::Schema::Artist';
  __PACKAGE__->table('artist');
  __PACKAGE__->add_column(bigint => { data_type => 'bigint' });
}
$schema->register_class(BigIntArtist => 'DBICTest::BigIntArtist');
$schema->storage->dbh_do(sub {
  $_[1]->do('ALTER TABLE artist ADD COLUMN bigint BIGINT');
});

# test upper/lower boundaries for sqlite and some values inbetween
# range is -(2**63) .. 2**63 - 1
for my $bi (qw/
  -9223372036854775808
  -9223372036854775807
  -8694837494948124658
  -6848440844435891639
  -5664812265578554454
  -5380388020020483213
  -2564279463598428141
  2442753333597784273
  4790993557925631491
  6773854980030157393
  7627910776496326154
  8297530189347439311
  9223372036854775806
  9223372036854775807
/) {
  $row = $schema->resultset('BigIntArtist')->create({ bigint => $bi });
  is ($row->bigint, $bi, "value in object correct ($bi)");

  TODO: {
    local $TODO = 'This perl does not seem to have 64bit int support - DBI roundtrip of large int will fail'
      unless $Config{ivsize} >= 8;

    $row->discard_changes;
    is ($row->bigint, $bi, "value in database correct ($bi)");
  }
}

done_testing;

# vim:sts=2 sw=2:
