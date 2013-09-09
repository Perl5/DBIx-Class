package DBICTest::Schema::EventTZWarning;

use strict;
use warnings;

use base qw/DBICTest::BaseResult/;

__PACKAGE__->load_components(qw/InflateColumn::DateTime/);

__PACKAGE__->table('event_tz_warning');

__PACKAGE__->add_columns(
  id => { data_type => 'integer', is_auto_increment => 1 },
  starts_at => {
    data_type => 'datetime',
    time_zone => "America/Chicago",
    locale    => 'de_DE',
  },
);

__PACKAGE__->set_primary_key('id');

sub _datetime_parser {
  require DateTime::Format::MySQL;
  DateTime::Format::MySQL->new();
}


1;
