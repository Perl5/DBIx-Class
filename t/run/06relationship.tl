sub run_tests {
my $schema = shift;

use strict;
use warnings;  
plan tests => 21;

# has_a test
my $cd = $schema->resultset("CD")->find(4);
my ($artist) = ($INC{'DBICTest/HelperRels'}
                  ? $cd->artist
                  : $cd->search_related('artist'));
is($artist->name, 'Random Boy Band', 'has_a search_related ok');

# has_many test with an order_by clause defined
$artist = $schema->resultset("Artist")->find(1);
my @cds = ($INC{'DBICTest/HelperRels'}
             ? $artist->cds
             : $artist->search_related('cds'));
is( $cds[1]->title, 'Spoonful of bees', 'has_many search_related with order_by ok' );

# search_related with additional abstract query
@cds = ($INC{'DBICTest/HelperRels'}
          ? $artist->cds({ title => { like => '%of%' } })
          : $artist->search_related('cds', { title => { like => '%of%' } } )
       );
is( $cds[1]->title, 'Forkful of bees', 'search_related with abstract query ok' );

# creating a related object
if ($INC{'DBICTest/HelperRels.pm'}) {
  $artist->add_to_cds({ title => 'Big Flop', year => 2005 });
} else {
  $artist->create_related( 'cds', {
      title => 'Big Flop',
      year => 2005,
  } );
}

is( ($artist->search_related('cds'))[3]->title, 'Big Flop', 'create_related ok' );

# count_related
is( $artist->count_related('cds'), 4, 'count_related ok' );

# set_from_related
my $track = $schema->resultset("Track")->create( {
  trackid => 1,
  cd => 3,
  position => 98,
  title => 'Hidden Track'
} );
$track->set_from_related( cd => $cd );

if ($INC{'DBICTest/HelperRels.pm'}) { # except inflated object
  is($track->disc->cdid, 4, 'set_from_related ok, including alternative accessor' );
} else {
  is( $track->cd, 4, 'set_from_related ok' );
}

# update_from_related, the same as set_from_related, but it calls update afterwards
$track = $schema->resultset("Track")->create( {
  trackid => 2,
  cd => 3,
  position => 99,
  title => 'Hidden Track'
} );
$track->update_from_related( cd => $cd );

my $t_cd = ($schema->resultset("Track")->search( cd => 4, position => 99 ))[0]->cd;

if ($INC{'DBICTest/HelperRels.pm'}) { # except inflated object
  is( $t_cd->cdid, 4, 'update_from_related ok' );
} else {
  is( $t_cd, 4, 'update_from_related ok' );
}

# find_or_create_related with an existing record
$cd = $artist->find_or_create_related( 'cds', { title => 'Big Flop' } );
is( $cd->year, 2005, 'find_or_create_related on existing record ok' );

# find_or_create_related creating a new record
$cd = $artist->find_or_create_related( 'cds', {
  title => 'Greatest Hits',
  year => 2006,
} );
is( $cd->title, 'Greatest Hits', 'find_or_create_related new record ok' );
@cds = $artist->search_related('cds');
is( ($artist->search_related('cds'))[4]->title, 'Greatest Hits', 'find_or_create_related new record search ok' );

$artist->delete_related( cds => { title => 'Greatest Hits' });
cmp_ok( $schema->resultset("CD")->search( title => 'Greatest Hits' ), '==', 0, 'delete_related ok' );

SKIP: {
  skip "relationship checking needs fixing", 1;
  # try to add a bogus relationship using the wrong cols
  eval {
      DBICTest::Schema::Artist->add_relationship(
          tracks => 'DBICTest::Schema::Track',
          { 'foreign.cd' => 'self.cdid' }
      );
  };
  like($@, qr/Unknown column/, 'failed when creating a rel with invalid key, ok');
}
  
# another bogus relationship using no join condition
eval {
    DBICTest::Schema::Artist->add_relationship( tracks => 'DBICTest::Track' );
};
like($@, qr/join condition/, 'failed when creating a rel without join condition, ok');

# many_to_many helper test
$cd = $schema->resultset("CD")->find(1);
my @producers = $cd->producers();
is( $producers[0]->name, 'Matt S Trout', 'many_to_many ok' );
is( $cd->producers_sorted->next->name, 'Bob The Builder', 'sorted many_to_many ok' );
is( $cd->producers_sorted(producerid => 3)->next->name, 'Fred The Phenotype', 'sorted many_to_many with search condition ok' );

# test undirected many-to-many relationship (e.g. "related artists")
my $undir_maps = $schema->resultset("Artist")->find(1)->artist_undirected_maps;
is($undir_maps->count, 1, 'found 1 undirected map for artist 1');

$undir_maps = $schema->resultset("Artist")->find(2)->artist_undirected_maps;
is($undir_maps->count, 1, 'found 1 undirected map for artist 2');

my $mapped_rs = $undir_maps->search_related('mapped_artists');

my @art = $mapped_rs->all;

cmp_ok(@art, '==', 2, "Both artist returned from map");

my $searched = $mapped_rs->search({'mapped_artists.artistid' => {'!=', undef}});

cmp_ok($searched->count, '==', 2, "Both artist returned from map after adding another condition");

# check join through cascaded has_many relationships
$artist = $schema->resultset("Artist")->find(1);
my $trackset = $artist->cds->search_related('tracks');
# LEFT join means we also see the trackless additional album...
cmp_ok($trackset->count, '==', 11, "Correct number of tracks for artist");

}

1;
