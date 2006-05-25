use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

eval { require DateTime::Format::MySQL };
plan skip_all => "Need DateTime::Format::MySQL for inflation tests" if $@;

plan tests => 2;

# inflation test
my $event = $schema->resultset("Event")->find(1);

isa_ok($event->starts_at, 'DateTime', 'DateTime returned');

is($event->starts_at, '2006-04-25T22:24:33', 'Correct date/time');

