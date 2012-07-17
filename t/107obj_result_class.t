package ResultClassInflator;

sub new { bless {}, __PACKAGE__ }

1;

package main;

use strict;
use warnings;

use Test::More tests => 6;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $source = $schema->source('CD');

lives_ok {
    $source->result_class('ResultClassInflator');
    is($source->result_class => 'ResultClassInflator', "result_class gives us back class");
    is($source->get_component_class('result_class') => 'ResultClassInflator',
        "and so does get_component_class");

    } 'Result class still works with class';
lives_ok {
    my $obj = ResultClassInflator->new();
    $source->result_class($obj);
    is($source->result_class => $obj, "result_class gives us back obj");
    is($source->get_component_class('result_class') => $obj, "and so does get_component_class");
    } 'Result class works with object';

done_testing;
