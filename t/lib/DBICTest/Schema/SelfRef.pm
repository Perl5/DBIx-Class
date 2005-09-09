package DBICTest::Schema::SelfRef;

use base 'DBIx::Class::Core';

__PACKAGE__->table('self_ref');
__PACKAGE__->add_columns(qw/id name/);
__PACKAGE__->set_primary_key('id');
__PACKAGE__->add_relationship(
    aliases => 'DBICTest::Schema::SelfRefAlias',
    { 'foreign.self_ref' => 'self.id' },
    { accessor => 'multi' }
);

1;
