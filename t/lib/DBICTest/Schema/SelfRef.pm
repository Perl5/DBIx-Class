package DBICTest::Schema::SelfRef;

use base 'DBIx::Class::Core';

__PACKAGE__->table('self_ref');
__PACKAGE__->add_columns(qw/id name/);
__PACKAGE__->set_primary_key('id');

1;
