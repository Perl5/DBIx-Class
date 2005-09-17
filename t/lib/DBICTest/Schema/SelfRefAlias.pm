package DBICTest::Schema::SelfRefAlias;

use base 'DBIx::Class::Core';

__PACKAGE__->table('self_ref_alias');
__PACKAGE__->add_columns(qw/self_ref alias/);
__PACKAGE__->set_primary_key('self_ref alias');

1;
