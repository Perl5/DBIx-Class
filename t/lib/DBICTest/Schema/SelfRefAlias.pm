package DBICTest::Schema::SelfRefAlias;

use base 'DBIx::Class::Core';

__PACKAGE__->table('self_ref_alias');
__PACKAGE__->add_columns(
  'self_ref' => {
    data_type => 'integer',
  },
  'alias' => {
    data_type => 'integer',
  },
);
__PACKAGE__->set_primary_key(qw/self_ref alias/);

1;
