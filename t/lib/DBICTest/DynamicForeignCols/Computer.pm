package DBICTest::DynamicForeignCols::Computer;

use warnings;
use strict;

use base 'DBIx::Class::Core';

__PACKAGE__->table('Computers');

__PACKAGE__->add_columns('id');

__PACKAGE__->set_primary_key('id');

__PACKAGE__->has_many(computer_test_links => 'DBICTest::DynamicForeignCols::TestComputer', 'computer_id');

1;
