package DBICTest::Schema::Event;

use strict;
use warnings;
use base qw/DBIx::Class::Core/;

__PACKAGE__->load_components(qw/InflateColumn::DateTime/);

__PACKAGE__->table('event');

__PACKAGE__->add_columns(
  id => { data_type => 'integer', is_auto_increment => 1 },
  starts_at => { data_type => 'datetime', datetime_undef_if_invalid => 1 },
  created_on => { data_type => 'timestamp' },
  varchar_date => { data_type => 'varchar', inflate_date => 1, size => 20, is_nullable => 1 },
  varchar_datetime => { data_type => 'varchar', inflate_datetime => 1, size => 20, is_nullable => 1 },
  skip_inflation => { data_type => 'datetime', inflate_datetime => 0, is_nullable => 1 },
);

__PACKAGE__->set_primary_key('id');

1;
