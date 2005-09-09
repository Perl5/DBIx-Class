package DBICTest::Schema::SelfRefAlias;

use base 'DBIx::Class::Core';

__PACKAGE__->table('self_ref_alias');
__PACKAGE__->add_columns(qw/self_ref alias/);
__PACKAGE__->set_primary_key('self_ref alias');
__PACKAGE__->add_relationship(
    self_ref => 'DBICTest::Schema::SelfRef',
    { 'foreign.id' => 'self.self_ref' },
    { accessor     => 'single' }

);
__PACKAGE__->add_relationship(
    alias => 'DBICTest::Schema::SelfRef',
    { 'foreign.id' => 'self.alias' },
    { accessor     => 'single' }
);

1;
