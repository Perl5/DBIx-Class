use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

eval { require DateTime::Format::MySQL };
plan skip_all => "Need DateTime::Format::MySQL for inflation tests" if $@;

plan tests => 4;

# inflation test
my $event = $schema->resultset("Event")->find(1);

isa_ok($event->starts_at, 'DateTime', 'DateTime returned');

# klunky, but makes older Test::More installs happy
my $starts = $event->starts_at . '';
is($starts, '2006-04-25T22:24:33', 'Correct date/time');

# create using DateTime
my $created = $schema->resultset('Event')->create({
    starts_at => DateTime->new(year=>2006, month=>6, day=>18)
});
my $created_start = $created->starts_at;

isa_ok($created->starts_at, 'DateTime', 'DateTime returned');
is($created_start, '2006-06-18T00:00:00', 'Correct date/time');
