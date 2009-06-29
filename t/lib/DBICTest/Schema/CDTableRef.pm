package # hide from PAUSE 
    DBICTest::Schema::CDTableRef;

use base qw/DBICTest::BaseResult/;
use DBIx::Class::ResultSource::View;

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');
__PACKAGE__->table(\'cd');
__PACKAGE__->result_source_instance->is_virtual(0);

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
  'year' => {
    data_type => 'varchar',
    size      => 100,
  },
  'genreid' => { 
    data_type => 'integer',
    is_nullable => 1,
  },
  'single_track' => {
    data_type => 'integer',
    is_nullable => 1,
    is_foreign_key => 1,
  }
);
__PACKAGE__->set_primary_key('cdid');
__PACKAGE__->add_unique_constraint([ qw/artist title/ ]);

__PACKAGE__->belongs_to( artist => 'DBICTest::Schema::Artist',
  'artist', { 
    is_deferrable => 1, 
});

1;
