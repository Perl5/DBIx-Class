use strict;
use warnings;

use Test::More;
use Test::Exception;

use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;
my $schema = DBICTest->init_schema();

lives_ok (sub {
  my $rs = $schema->resultset( 'CD' )->search(
    {
      'producer.name'   => 'blah',
      'producer_2.name' => 'foo',
    },
    {
      'join' => [
        { cd_to_producer => 'producer' },
        { cd_to_producer => 'producer' },
      ],
      'prefetch' => [
        'artist',
        { cd_to_producer => { producer => 'producer_to_cd' } },
      ],
    }
  );

  my @executed = $rs->all();

  is_same_sql_bind (
    $rs->as_query,
    '(
      SELECT  me.cdid, me.artist, me.title, me.year, me.genreid, me.single_track,
              artist.artistid, artist.name, artist.rank, artist.charfield,
              cd_to_producer.cd, cd_to_producer.producer, cd_to_producer.attribute,
              producer.producerid, producer.name,
              producer_to_cd.cd, producer_to_cd.producer, producer_to_cd.attribute
        FROM cd me
        LEFT JOIN cd_to_producer cd_to_producer
          ON cd_to_producer.cd = me.cdid
        LEFT JOIN producer producer
          ON producer.producerid = cd_to_producer.producer
        LEFT JOIN cd_to_producer producer_to_cd
          ON producer_to_cd.producer = producer.producerid
        LEFT JOIN cd_to_producer cd_to_producer_2
          ON cd_to_producer_2.cd = me.cdid
        LEFT JOIN producer producer_2
          ON producer_2.producerid = cd_to_producer_2.producer
        JOIN artist artist ON artist.artistid = me.artist
      WHERE ( ( producer.name = ? AND producer_2.name = ? ) )
      ORDER BY me.cdid
    )',
    [
      [ { sqlt_datatype => 'varchar', dbic_colname => 'producer.name', sqlt_size => 100 }
          => 'blah' ],
      [ { sqlt_datatype => 'varchar', dbic_colname => 'producer_2.name', sqlt_size => 100 }
          => 'foo' ],
    ],
  );

}, 'Complex join parsed/executed properly');

my @rs1a_results = $schema->resultset("Artist")->search_related('cds', {title => 'Forkful of bees'}, {order_by => 'title'});
is($rs1a_results[0]->title, 'Forkful of bees', "bare field conditions okay after search related");
my $rs1 = $schema->resultset("Artist")->search({ 'tags.tag' => 'Blue' }, { join => {'cds' => 'tracks'}, prefetch => {'cds' => 'tags'} });
my @artists = $rs1->all;
cmp_ok(@artists, '==', 2, "Two artists returned");

my $rs2 = $rs1->search({ artistid => '1' }, { join => {'cds' => {'cd_to_producer' => 'producer'} } });
my @artists2 = $rs2->search({ 'producer.name' => 'Matt S Trout' });
my @cds = $artists2[0]->cds;
cmp_ok(scalar @cds, '==', 1, "condition based on inherited join okay");

my $rs3 = $rs2->search_related('cds');

cmp_ok(scalar($rs3->all), '==', 15, "All cds for artist returned");

cmp_ok($rs3->count, '==', 15, "All cds for artist returned via count");

my $rs4 = $schema->resultset("CD")->search({ 'artist.artistid' => '1' }, { join => ['tracks', 'artist'], prefetch => 'artist' });
my @rs4_results = $rs4->all;

is($rs4_results[0]->cdid, 1, "correct artist returned");

my $rs5 = $rs4->search({'tracks.title' => 'Sticky Honey'});
is($rs5->count, 1, "search without using previous joins okay");

my $record_rs = $schema->resultset("Artist")->search(undef, { join => 'cds' })->search(undef, { prefetch => { 'cds' => 'tracks' }});
my $record_jp = $record_rs->next;
ok($record_jp, "prefetch on same rel okay");

my $artist = $schema->resultset("Artist")->find(1);
my $cds = $artist->cds;
is($cds->find(2)->title, 'Forkful of bees', "find on has many rs okay");

my $cd = $cds->search({'me.title' => 'Forkful of bees'}, { prefetch => 'tracks' })->first;
my @tracks = $cd->tracks->all;
is(scalar(@tracks), 3, 'right number of prefetched tracks after has many');

#causes ambig col error due to order_by
#my $tracks_rs = $cds->search_related('tracks', { 'tracks.position' => '2', 'disc.title' => 'Forkful of bees' });
#my $first_tracks_rs = $tracks_rs->first;

my $related_rs = $schema->resultset("Artist")->search({ name => 'Caterwauler McCrae' })->search_related('cds', { year => '2001'})->search_related('tracks', { 'position' => '2' });
is($related_rs->first->trackid, '5', 'search related on search related okay');

#causes ambig col error due to order_by
#$related_rs->search({'cd.year' => '2001'}, {join => ['cd', 'cd']})->all;

my $title = $schema->resultset("Artist")->search_related('twokeys')->search_related('cd')->search({'tracks.position' => '2'}, {join => 'tracks', order_by => 'tracks.trackid'})->next->title;
is($title, 'Forkful of bees', 'search relateds with order by okay');

my $prod_rs = $schema->resultset("CD")->find(1)->producers_sorted;
my $prod_rs2 = $prod_rs->search({ name => 'Matt S Trout' });
my $prod_first = $prod_rs2->first;
is($prod_first->id, '1', 'somewhat pointless search on rel with order_by on it okay');

my $prod_map_rs = $schema->resultset("Artist")->find(1)->cds->search_related('cd_to_producer', {}, { join => 'producer', prefetch => 'producer' });
ok($prod_map_rs->next->producer, 'search related with prefetch okay');

my $stupid = $schema->resultset("Artist")->search_related('artist_undirected_maps', {}, { prefetch => 'artist1' })->search_related('mapped_artists')->search_related('cds', {'cds.cdid' => '2'}, { prefetch => 'tracks' });

my $cd_final = $schema->resultset("Artist")->search_related('artist_undirected_maps', {}, { prefetch => 'artist1' })->search_related('mapped_artists')->search_related('cds', {'cds.cdid' => '2'}, { prefetch => 'tracks' })->first;
is($cd_final->cdid, '2', 'bonkers search_related-with-join-midway okay');

# should end up with cds and cds_2 joined
my $merge_rs_1 = $schema->resultset("Artist")->search({ 'cds_2.cdid' => '2' }, { join => ['cds', 'cds'] });
is(scalar(@{$merge_rs_1->{attrs}->{join}}), 2, 'both joins kept');
ok($merge_rs_1->next, 'query on double joined rel runs okay');

# should only end up with cds joined
my $merge_rs_2 = $schema->resultset("Artist")->search({ }, { join => 'cds' })->search({ 'cds.cdid' => '2' }, { join => 'cds' });
is(scalar(@{$merge_rs_2->{attrs}->{join}}), 1, 'only one join kept when inherited');
my $merge_rs_2_cd = $merge_rs_2->next;

lives_ok (sub {

  my @rs_with_prefetch = $schema->resultset('TreeLike')
                                ->search(
    {'me.id' => 1},
    {
    prefetch => [ 'parent', { 'children' => 'parent' } ],
    });

}, 'pathological prefetch ok');

my $rs = $schema->resultset("Artist")->search({}, { join => 'twokeys' });
my $second_search_rs = $rs->search({ 'cds_2.cdid' => '2' }, { join =>
['cds', 'cds'] });
is(scalar(@{$second_search_rs->{attrs}->{join}}), 3, 'both joins kept');
ok($second_search_rs->next, 'query on double joined rel runs okay');

# test joinmap pruner
lives_ok ( sub {
  my $rs = $schema->resultset('Artwork')->search (
    {
    },
    {
      distinct => 1,
      join => [
        { artwork_to_artist => 'artist' },
        { cd => 'artist' },
      ],
    },
  );

  is_same_sql_bind (
    $rs->count_rs->as_query,
    '(
      SELECT COUNT( * )
        FROM (
          SELECT me.cd_id
            FROM cd_artwork me
            JOIN cd cd ON cd.cdid = me.cd_id
            JOIN artist artist_2 ON artist_2.artistid = cd.artist
          GROUP BY me.cd_id
        ) me
    )',
    [],
  );

  ok (defined $rs->count);
});

# make sure multiplying endpoints do not lose heir join-path
lives_ok (sub {
  my $rs = $schema->resultset('CD')->search (
    { },
    { join => { artwork => 'images' } },
  )->get_column('cdid');

  is_same_sql_bind (
    $rs->as_query,
    '(
      SELECT me.cdid
        FROM cd me
        LEFT JOIN cd_artwork artwork
          ON artwork.cd_id = me.cdid
        LEFT JOIN images images
          ON images.artwork_id = artwork.cd_id
    )',
    [],
  );

  # execution
  $rs->next;
});

done_testing;
