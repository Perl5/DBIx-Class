use strict;
use warnings;

use Test::More;
use Test::Exception;
use Test::Warn;
use lib qw(t/lib);
use DBICTest;

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

# make sure the side-effects of RT#67581 do not result in data loss
my $row;
warnings_exist { $row = $ars->create ({ name => 'alpha rank', rank => 'abc' }) }
  [qr/Non-numeric value supplied for column 'rank' despite the numeric datatype/],
  'proper warning on string insertion into an numeric column'
;
$row->discard_changes;
is ($row->rank, 'abc', 'proper rank inserted into database');

done_testing;

# vim:sts=2 sw=2:
