use strict;
use warnings;

use Test::More;
use Test::Warn;
use Try::Tiny;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $event = $schema->resultset("Event")->find(1);

ok(
    $event->update(
        {
            starts_at => \[
                'MAX(datetime(?), datetime(?))', '2006-04-25T22:24:33',
                '2007-04-25T22:24:33',
            ]
        }
    ),
    'update without error'
);

$event = $event->get_from_storage();

is(
    $event->starts_at . '',
    '2007-04-25T22:24:33',
    'starts_at updated properly'
);

done_testing;
