package    # hide from PAUSE
    ViewDeps::Result::JustATable;
## Used in 105view_deps.t

use base qw(DBIx::Class::Core);

__PACKAGE__->table('just_a_table');

__PACKAGE__->add_columns(
    id   => { data_type => 'integer', is_auto_increment => 1 },
    name => { data_type => 'varchar', size              => 255 }
);

__PACKAGE__->set_primary_key('id');

__PACKAGE__->has_many( 'bars', 'ViewDeps::Result::Bar',
    { 'foreign.b' => 'self.id' } );

1;
