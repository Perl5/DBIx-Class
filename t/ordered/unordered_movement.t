use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $cd = $schema->resultset('CD')->next;
$cd->tracks->delete;

$schema->resultset('CD')->related_resultset('tracks')->delete;

is $cd->tracks->count, 0, 'No tracks';

$cd->create_related('tracks', { title => "t_$_", position => $_ })
  for (4,2,3,1,5);

is $cd->tracks->count, 5, 'Created 5 tracks';

# a txn should force the implicit pos reload, regardless of order
$schema->txn_do(sub {
  $cd->tracks->delete_all
});

is $cd->tracks->count, 0, 'Successfully deleted everything';

done_testing;
