use strict;
use warnings;

use Test::More;
use Test::Exception;

use lib qw(t/lib);
use DBICTest;

plan tests => 5;

my $schema = DBICTest->init_schema();

$schema->storage->dbh->do("PRAGMA foreign_keys = ON");

my $artist_rs = $schema->resultset("Artist");
my $map_rs    = $schema->resultset("ArtistUndirectedMap");

my $artist1 = $artist_rs->create({});
my $artist2 = $artist_rs->create({});

$map_rs->create({id1 => $artist1->id, id2 => $artist2->id});

my $count1 = $map_rs->search({id1 => $artist1->id})->count;
is($count1, 1, "Have a count of artist1");

# disable perl cascade
my $rel = $artist1->result_source->relationship_info('artist_undirected_maps');
$rel->{attrs}{cascade_delete} = 0;

# This must fail, or the DB is doing cascade deletes
my $db_cascade = eval { $artist1->delete; 1; };

SKIP: {
  skip "Database is performing cascade so test is pointless", 3
    if $db_cascade;

  # check both artists are still in database after a failed delete
  ok($artist1->in_storage, "Artist1 is still in storage");
  ok($artist2->in_storage, "Artist2 is still in storage");

  # perform cascade delete in perl
  $rel->{attrs}{cascade_delete} = 1;
  $artist1->delete;

  my $after = $map_rs->search({id1 => $artist1->id})->count;
  is($after, 0,  "map rows got deleted");

  ok(!$artist1->in_storage, "Artist1 is not in storage");
}
