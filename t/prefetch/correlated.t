use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;

my $schema = DBICTest->init_schema();
my $orig_debug = $schema->storage->debug;

my $cdrs = $schema->resultset('CD')->search({ 'me.artist' => { '!=', 2 }});

my $cd_data = { map {
  $_->cdid => {
    siblings => $cdrs->search ({ artist => $_->get_column('artist') })->count - 1,
    track_titles => [ map { $_->title } ($_->tracks->all) ],
  },
} ( $cdrs->all ) };

my $c_rs = $cdrs->search ({}, {
  prefetch => 'tracks',
  '+columns' => { sibling_count => $cdrs->search(
      {
        'siblings.artist' => { -ident => 'me.artist' },
        'siblings.cdid' => { '!=' => ['-and', { -ident => 'me.cdid' }, 23414] },
      }, { alias => 'siblings' },
    )->count_rs->as_query,
  },
});

is_same_sql_bind(
  $c_rs->as_query,
  '(
    SELECT me.cdid, me.artist, me.title, me.year, me.genreid, me.single_track,
           (SELECT COUNT( * )
              FROM cd siblings
            WHERE siblings.artist = me.artist
              AND siblings.cdid != me.cdid
              AND siblings.cdid != ?
              AND me.artist != ?
           ),
           tracks.trackid, tracks.cd, tracks.position, tracks.title, tracks.last_updated_on, tracks.last_updated_at
      FROM cd me
      LEFT JOIN track tracks
        ON tracks.cd = me.cdid
    WHERE me.artist != ?
    ORDER BY tracks.cd
  )',
  [

    # subselect
    [ { sqlt_datatype => 'integer', dbic_colname => 'siblings.cdid' }
      => 23414 ],

    [ { sqlt_datatype => 'integer', dbic_colname => 'me.artist' }
      => 2 ],

    # outher WHERE
    [ { sqlt_datatype => 'integer', dbic_colname => 'me.artist' }
      => 2 ],
  ],
  'Expected SQL on correlated realiased subquery'
);

my $queries = 0;
$schema->storage->debugcb(sub { $queries++; });
$schema->storage->debug(1);

is_deeply (
  { map
    { $_->cdid => {
      track_titles => [ map { $_->title } ($_->tracks->all) ],
      siblings => $_->get_column ('sibling_count'),
    } }
    $c_rs->all
  },
  $cd_data,
  'Proper information retrieved from correlated subquery'
);

is ($queries, 1, 'Only 1 query fired to retrieve everything');

$schema->storage->debug($orig_debug);
$schema->storage->debugcb(undef);

# now add an unbalanced select/as pair
$c_rs = $c_rs->search ({}, {
  '+select' => $cdrs->search(
    { 'siblings.artist' => { -ident => 'me.artist' } },
    { alias => 'siblings', columns => [
      { first_year => { min => 'year' }},
      { last_year => { max => 'year' }},
    ]},
  )->as_query,
  '+as' => [qw/active_from active_to/],
});

is_same_sql_bind(
  $c_rs->as_query,
  '(
    SELECT me.cdid, me.artist, me.title, me.year, me.genreid, me.single_track,
           (SELECT COUNT( * )
              FROM cd siblings
            WHERE siblings.artist = me.artist
              AND siblings.cdid != me.cdid
              AND siblings.cdid != ?
              AND me.artist != ?
           ),
           (SELECT MIN( year ), MAX( year )
              FROM cd siblings
            WHERE siblings.artist = me.artist
              AND me.artist != ?
           ),
           tracks.trackid, tracks.cd, tracks.position, tracks.title, tracks.last_updated_on, tracks.last_updated_at
      FROM cd me
      LEFT JOIN track tracks
        ON tracks.cd = me.cdid
    WHERE me.artist != ?
    ORDER BY tracks.cd
  )',
  [

    # first subselect
    [ { sqlt_datatype => 'integer', dbic_colname => 'siblings.cdid' }
      => 23414 ],

    [ { sqlt_datatype => 'integer', dbic_colname => 'me.artist' }
      => 2 ],

    # second subselect
    [ { sqlt_datatype => 'integer', dbic_colname => 'me.artist' }
      => 2 ],

    # outher WHERE
    [ { sqlt_datatype => 'integer', dbic_colname => 'me.artist' }
      => 2 ],
  ],
  'Expected SQL on correlated realiased subquery'
);

done_testing;
