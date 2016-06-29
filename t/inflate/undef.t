BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;

use Test::More;

use DateTime;

use DBICTest;
my $schema = DBICTest->init_schema();

my $date = DateTime->new(year => 1900, month => 1, day => 1);

my $res = $schema->resultset('Event')->create({ starts_at => $date, created_on => DateTime->now(), });

$res->varchar_datetime($date);
is($res->varchar_datetime, $date, 'Setting an inflated column to an object stores the right value in the object');
isa_ok($res->varchar_datetime, 'DateTime', 'Can store objects in inflated columns');

$res->varchar_datetime($date);
$res->varchar_datetime(undef);
is($res->varchar_datetime, undef, 'After storing undef in an object using the accessor, the accessor returns the right value');
is($res->get_inflated_column('varchar_datetime'), undef, '. . . and get_inflated_column returns the right value');
is($res->get_column('varchar_datetime'), undef, '. . . and get_column returns the right value');

$res->varchar_datetime($date);
$res->set_inflated_columns({ varchar_datetime => undef, });
is($res->varchar_datetime, undef, 'After storing undef in an object using set_inflated_columns, the accessor returns the right value');
is($res->get_inflated_column('varchar_datetime'), undef, '. . . and get_inflated_column returns the right value');
is($res->get_column('varchar_datetime'), undef, '. . . and get_column returns the right value');

$res->varchar_datetime($date);
$res->set_inflated_column(varchar_datetime => undef);
is($res->varchar_datetime, undef, 'After storing undef in an object using set_inflated_column, the accessor returns the right value');
is($res->get_inflated_column('varchar_datetime'), undef, '. . . and get_inflated_column returns the right value');
is($res->get_column('varchar_datetime'), undef, '. . . and get_column returns the right value');

undef $res;

done_testing();
