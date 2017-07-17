BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;

use Test::Exception tests => 1;

use DBICTest;
use DBICTest::Schema;
use DBIx::Class::ResultSource::Table;

my $schema = DBICTest->init_schema();

my $foo = DBIx::Class::ResultSource::Table->new({ name => "foo" });
my $bar = DBIx::Class::ResultSource::Table->new({ name => "bar" });

lives_ok {
    $schema->register_source(foo => $foo);
    $schema->register_source(bar => $bar);
} 'multiple classless sources can be registered';
