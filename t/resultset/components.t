use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBICTest;
use Data::Dumper;
my $schema = DBICTest->init_schema;

isa_ok $schema->resultset('Artist'), 'A::Useless', 'Artist RS';
ok !$schema->resultset('CD')->isa('A::Useless'), 'CD RS is not A::Useless';

my @classes = ('DBICTest::BaseResultSet::WITH::_A__Useless::_A__MoarUseless',
               'A::Useless',
               'A::MoarUseless',
               'DBICTest::BaseResultSet',
               'DBIx::Class::ResultSet',
               'DBIx::Class',
               'DBIx::Class::Componentised',
               'Class::C3::Componentised',
               'Class::Accessor::Grouped');

is_deeply(mro::get_linear_isa(ref $schema->resultset('Artist')), \@classes, 'Proper ISA Stack Order');

isa_ok $schema->resultset('Employee'), 'A::Useless', 'Employee RS';

done_testing;
