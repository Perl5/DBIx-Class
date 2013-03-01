package # hide from PAUSE
    DBICTest::Schema::CollectionObject;

use warnings;
use strict;

use base qw/DBICTest::BaseResult/;

__PACKAGE__->table('collection_object');
__PACKAGE__->add_columns(
  'collection' => {
    data_type => 'integer',
  },
  'object' => {
    data_type => 'integer',
  },
);
__PACKAGE__->set_primary_key(qw/collection object/);

__PACKAGE__->refers_to( collection => "DBICTest::Schema::Collection",
                         { "foreign.collectionid" => "self.collection" }
                       );
__PACKAGE__->refers_to( object => "DBICTest::Schema::TypedObject",
                         { "foreign.objectid" => "self.object" }
                       );

1;
