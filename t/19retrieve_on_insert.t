use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();
$schema->storage->sql_maker->quote_char('"');

my $rs = $schema->resultset ('Artist');

my $obj;
lives_ok { $obj = $rs->create ({ name => 'artistA' }) } 'Default insert successful';
is ($obj->rank, undef, 'Without retrieve_on_insert, check rank');

$rs->result_source->add_columns(
    '+rank' => { retrieve_on_insert => 1 }
);

lives_ok { $obj = $rs->create ({ name => 'artistB' }) } 'Default insert successful';
is ($obj->rank, 13, 'With retrieve_on_insert, check rank');

done_testing;
