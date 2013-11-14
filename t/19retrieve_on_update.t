BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;

use Test::More;
use Test::Exception;
use DBICTest;

# basically copies the test for retrieve_on_insert due to its
# similarity in nature

my $schema = DBICTest->init_schema( quote_names => 1 );

my $rs = $schema->resultset ('Artist');

my $obj;
lives_ok { $obj = $rs->create ({ name => 'artistA', rank => 13 }) } 'insert successful';
is ($obj->rank, 13, 'initial valus is normal');

# increment rank using raw sql
lives_ok { $obj->update({ rank => \'rank + 1' }) }, "raw sql processed without errors";

isa_ok( $obj->rank, "SCALAR", "rank after raw sql update" );

$obj->discard_changes;

is( $obj->rank, 14, "rank incremented in db" );

$rs->result_source->add_columns(
    '+rank' => { retrieve_on_update => 1 }
);

## increment again
$obj->update({ rank => \'rank + 1' });

is( $obj->rank, 14, "rank updated without discarding changes to refetch" );

lives_ok { $obj = $rs->create ({ name => 'artistB', rank => 13 }) } 'insert #2 successful';
$obj->update({ rank => \'rank + 1' });
is($obj->rank, 14, 'With retrieve_on_update, check rank');

done_testing;
