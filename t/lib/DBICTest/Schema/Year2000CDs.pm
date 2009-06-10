package # hide from PAUSE 
    DBICTest::Schema::Year2000CDs;
## Used in 104view.t

use base qw/DBICTest::BaseResult/;
use DBIx::Class::ResultSource::View;

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('year2000cds');
__PACKAGE__->result_source_instance->view_definition(
  "SELECT cdid, artist, title FROM cd WHERE year ='2000'"
);
__PACKAGE__->add_columns(
  'cdid' => {
    data_type => 'integer',
    is_auto_increment => 1,
  },
  'artist' => {
    data_type => 'integer',
  },
  'title' => {
    data_type => 'varchar',
    size      => 100,
  },

);
__PACKAGE__->set_primary_key('cdid');
__PACKAGE__->add_unique_constraint([ qw/artist title/ ]);

1;
