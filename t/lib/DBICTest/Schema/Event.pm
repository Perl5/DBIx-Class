package DBICTest::Schema::Event;

use strict;
use warnings;
use base qw/DBICTest::BaseResult/;

__PACKAGE__->load_components(qw/InflateColumn::DateTime/);

__PACKAGE__->table('event');

__PACKAGE__->add_columns(
  id => { data_type => 'integer', is_auto_increment => 1 },

# this MUST be 'date' for the Firebird and SQLAnywhere tests
  starts_at => { data_type => 'date', datetime_undef_if_invalid => 1 },

  created_on => { data_type => 'timestamp' },
  varchar_date => { data_type => 'varchar', size => 20, is_nullable => 1 },
  varchar_datetime => { data_type => 'varchar', size => 20, is_nullable => 1 },
  skip_inflation => { data_type => 'datetime', inflate_datetime => 0, is_nullable => 1 },
  ts_without_tz => { data_type => 'datetime', is_nullable => 1 }, # used in EventTZPg
);

__PACKAGE__->set_primary_key('id');

# Test add_columns '+colname' to augment a column definition.
__PACKAGE__->add_columns(
  '+varchar_date' => {
    inflate_date => 1,
  },
  '+varchar_datetime' => {
    inflate_datetime => 1,
  },
);

1;
