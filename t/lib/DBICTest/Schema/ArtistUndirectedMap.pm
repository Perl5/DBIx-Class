package DBICTest::Schema::ArtistUndirectedMap;

use base 'DBIx::Class::Core';

__PACKAGE__->table('artist_undirected_map');
__PACKAGE__->add_columns(qw/id1 id2/);
__PACKAGE__->set_primary_key(qw/id1 id2/);

1;
