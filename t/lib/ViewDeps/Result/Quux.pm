package    # hide from PAUSE
    ViewDeps::Result::Quux;

use strict;
use warnings;
use base qw(DBIx::Class::Core);

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');
__PACKAGE__->table('quux');

__PACKAGE__->result_source_instance->view_definition(
    "select * from quux");

__PACKAGE__->add_columns(
    etc => { data_type => 'text' },
    c  => { data_type => 'integer', is_nullable => 1 }
);

__PACKAGE__->set_primary_key('c');

__PACKAGE__->belongs_to( 'foo', 'ViewDeps::Result::Foo',
    { 'foreign.a' => 'self.c' } );

1;
