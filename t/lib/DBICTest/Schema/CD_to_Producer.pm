package DBICTest::Schema::CD_to_Producer;

use base 'DBIx::Class::Core';

__PACKAGE__->table('cd_to_producer');
__PACKAGE__->add_columns(
  cd => { data_type => 'integer' },
  producer => { data_type => 'integer' },
);
__PACKAGE__->set_primary_key(qw/cd producer/);

1;
