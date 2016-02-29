BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;

use Test::More;

use DBICTest ':DiffSQL';

my $schema = DBICTest->init_schema;

is_same_sql_bind(
  $schema->resultset('Artist')->search ({}, {for => 'update'})->as_query,
  '(SELECT me.artistid, me.name, me.rank, me.charfield FROM artist me)', [],
);

done_testing;
