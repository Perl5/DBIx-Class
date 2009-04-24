package DBICTest::Schema::Demographic;

use strict;

use base 'DBIx::Class::Core';

__PACKAGE__->table('demographic');
__PACKAGE__->add_columns(
    demographicid => {
      data_type => 'integer',
      is_auto_increment => 1,
    },
    name => {
      data_type => 'varchar',
      size => 100,
    },
);
__PACKAGE__->set_primary_key('demographicid');
__PACKAGE__->add_unique_constraint ( demographic_name => [qw/name/] );

1;
