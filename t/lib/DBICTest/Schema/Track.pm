package # hide from PAUSE 
    DBICTest::Schema::Track;

use base 'DBIx::Class::Core';

DBICTest::Schema::Track->table('track');
DBICTest::Schema::Track->add_columns(
  'trackid' => {
    data_type => 'integer',
    is_auto_increment => 1,
  },
  'cd' => {
    data_type => 'integer',
  },
  'position' => {
    data_type => 'integer',
    accessor => 'pos',
  },
  'title' => {
    data_type => 'varchar',
  },
);
DBICTest::Schema::Track->set_primary_key('trackid');

1;
