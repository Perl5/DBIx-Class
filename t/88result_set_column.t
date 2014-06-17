use strict;
use warnings;

use Test::More;
use Test::Warn;
use Test::Exception;

# MASSIVE FIXME - there is a hole in ::RSC / as_subselect_rs
# losing the order. Needs a rework/extract of the realiaser,
# and that's a whole another bag of dicks
BEGIN { $ENV{DBIC_SHUFFLE_UNORDERED_RESULTSETS} = 0 }

use lib qw(t/lib);
use DBICTest ':DiffSQL';

my $schema = DBICTest->init_schema();

my $rs = $schema->resultset("CD");

cmp_ok (
  $rs->count,
    '>',
  $rs->search ({}, {columns => ['year'], distinct => 1})->count,
  'At least one year is the same in rs'
);

my $rs_title = $rs->get_column('title');
my $rs_year = $rs->get_column('year');
my $max_year = $rs->get_column(\'MAX (year)');

my @all_titles = $rs_title->all;
cmp_ok(scalar @all_titles, '==', 5, "five titles returned");

my @nexted_titles;
while (my $r = $rs_title->next) {
  push @nexted_titles, $r;
}

is_deeply (\@all_titles, \@nexted_titles, 'next works');

is_deeply( [ sort $rs_year->func('DISTINCT') ], [ 1997, 1998, 1999, 2001 ],  "wantarray context okay");
ok ($max_year->next == $rs_year->max, q/get_column (\'FUNC') ok/);

cmp_ok($rs_year->max, '==', 2001, "max okay for year");
is($rs_title->min, 'Caterwaulin\' Blues', "min okay for title");

cmp_ok($rs_year->sum, '==', 9996, "three artists returned");

my $rso_year = $rs->search({}, { order_by => 'cdid' })->get_column('year');
is($rso_year->next, 1999, "reset okay");

is($rso_year->first, 1999, "first okay");

warnings_exist (sub {
  is($rso_year->single, 1999, "single okay");
}, qr/Query returned more than one row/, 'single warned');


# test distinct propagation
is_deeply (
  [sort $rs->search ({}, { distinct => 1 })->get_column ('year')->all],
  [sort $rs_year->func('distinct')],
  'distinct => 1 is passed through properly',
);

# test illogical distinct
my $dist_rs = $rs->search ({}, {
  columns => ['year'],
  distinct => 1,
  order_by => { -desc => [qw( cdid year )] },
});

is_same_sql_bind(
  $dist_rs->as_query,
  '(
    SELECT me.year
      FROM cd me
    GROUP BY me.year
    ORDER BY MAX(cdid) DESC, year DESC
  )',
  [],
  'Correct SQL on external-ordered distinct',
);

is_same_sql_bind(
  $dist_rs->count_rs->as_query,
  '(
    SELECT COUNT( * )
      FROM (
        SELECT me.year
          FROM cd me
        GROUP BY me.year
      ) me
  )',
  [],
  'Correct SQL on count of external-orderdd distinct',
);

is (
  $dist_rs->count_rs->next,
  4,
  'Correct rs-count',
);

is (
  $dist_rs->count,
  4,
  'Correct direct count',
);

# test +select/+as for single column
my $psrs = $schema->resultset('CD')->search({},
    {
        '+select'   => \'MAX(year)',
        '+as'       => 'last_year'
    }
);
lives_ok(sub { $psrs->get_column('last_year')->next }, '+select/+as additional column "last_year" present (scalar)');
dies_ok(sub { $psrs->get_column('noSuchColumn')->next }, '+select/+as nonexistent column throws exception');

# test +select/+as for overriding a column
$psrs = $schema->resultset('CD')->search({},
    {
        'select'   => \"'The Final Countdown'",
        'as'       => 'title'
    }
);
is($psrs->get_column('title')->next, 'The Final Countdown', '+select/+as overridden column "title"');


# test +select/+as for multiple columns
$psrs = $schema->resultset('CD')->search({},
    {
        '+select'   => [ \'LENGTH(title) AS title_length', 'title' ],
        '+as'       => [ 'tlength', 'addedtitle' ]
    }
);
lives_ok(sub { $psrs->get_column('tlength')->next }, '+select/+as multiple additional columns, "tlength" column present');
lives_ok(sub { $psrs->get_column('addedtitle')->next }, '+select/+as multiple additional columns, "addedtitle" column present');

# test that +select/+as specs do not leak
is_same_sql_bind (
  $psrs->get_column('year')->as_query,
  '(SELECT me.year FROM cd me)',
  [],
  'Correct SQL for get_column/as'
);

is_same_sql_bind (
  $psrs->get_column('addedtitle')->as_query,
  '(SELECT me.title FROM cd me)',
  [],
  'Correct SQL for get_column/+as col'
);

is_same_sql_bind (
  $psrs->get_column('tlength')->as_query,
  '(SELECT LENGTH(title) AS title_length FROM cd me)',
  [],
  'Correct SQL for get_column/+as func'
);

# test that order_by over a function forces a subquery
lives_ok ( sub {
  is_deeply (
    [ $psrs->search ({}, { order_by => { -desc => 'title_length' } })->get_column ('title')->all ],
    [
      "Generic Manufactured Singles",
      "Come Be Depressed With Us",
      "Caterwaulin' Blues",
      "Spoonful of bees",
      "Forkful of bees",
    ],
    'Subquery count induced by aliased ordering function',
  );
});

# test for prefetch not leaking
{
  my $rs = $schema->resultset("CD")->search({}, { prefetch => 'artist' });
  my $rsc = $rs->get_column('year');
  is( $rsc->{_parent_resultset}->{attrs}->{prefetch}, undef, 'prefetch wiped' );
}

# test sum()
is ($schema->resultset('BooksInLibrary')->get_column ('price')->sum, 125, 'Sum of a resultset works correctly');

# test sum over search_related
my $owner = $schema->resultset('Owners')->find ({ name => 'Newton' });
ok ($owner->books->count > 1, 'Owner Newton has multiple books');
is ($owner->search_related ('books')->get_column ('price')->sum, 60, 'Correctly calculated price of all owned books');


# make sure joined/prefetched get_column of a PK dtrt
$rs->reset;
my $j_rs = $rs->search ({}, { join => 'tracks' })->get_column ('cdid');
is_deeply (
  [ sort $j_rs->all ],
  [ sort map { my $c = $rs->next; ( ($c->id) x $c->tracks->count ) } (1 .. $rs->count) ],
  'join properly explodes amount of rows from get_column',
);

$rs->reset;
my $p_rs = $rs->search ({}, { prefetch => 'tracks' })->get_column ('cdid');
is_deeply (
  [ sort $p_rs->all ],
  [ sort $rs->get_column ('cdid')->all ],
  'prefetch properly collapses amount of rows from get_column',
);

$rs->reset;
my $pob_rs = $rs->search({}, {
  select   => ['me.title', 'tracks.title'],
  prefetch => 'tracks',
  order_by => [{-asc => ['position']}],
  group_by => ['me.title', 'tracks.title'],
});
is_same_sql_bind (
  $pob_rs->get_column("me.title")->as_query,
  '(SELECT me.title FROM (SELECT me.title, tracks.title FROM cd me LEFT JOIN track tracks ON tracks.cd = me.cdid GROUP BY me.title, tracks.title ORDER BY position ASC) me)',
  [],
  'Correct SQL for prefetch/order_by/group_by'
);

# test aggregate on a function (create an extra track on one cd)
{
  my $tr_rs = $schema->resultset("Track");
  $tr_rs->create({ cd => 2, title => 'dealbreaker' });

  is(
    $tr_rs->get_column('cd')->max,
    5,
    "Correct: Max cd in Track is 5"
  );

  my $track_counts_per_cd_via_group_by = $tr_rs->search({}, {
    columns => [ 'cd', { cnt => { count => 'trackid', -as => 'cnt' } } ],
    group_by => 'cd',
  })->get_column('cnt');

  is ($track_counts_per_cd_via_group_by->max, 4, 'Correct max tracks per cd');
  is ($track_counts_per_cd_via_group_by->min, 3, 'Correct min tracks per cd');
  is (
    sprintf('%0.1f', $track_counts_per_cd_via_group_by->func('avg') ),
    '3.2',
    'Correct avg tracks per cd'
  );
}

# test exotic scenarious (create a track-less cd)
# "How many CDs (not tracks) have been released per year where a given CD has at least one track and the artist isn't evancarroll?"
{

  $schema->resultset('CD')->create({ artist => 1, title => 'dealbroker no tracks', year => 2001 });

  my $yp1 = \[ 'year + ?', 1 ];

  my $rs = $schema->resultset ('CD')->search (
    { 'artist.name' => { '!=', 'evancarrol' }, 'tracks.trackid' => { '!=', undef } },
    {
      order_by => 'me.year',
      join => [qw(artist tracks)],
      columns => [
        'year',
        { cnt => { count => 'me.cdid' } },
        {  year_plus_one => $yp1 },
      ],
    },
  );

  my $rstypes = {
    'explicitly grouped' => $rs->search_rs({}, { group_by => [ 'year', $yp1 ] } ),
    'implicitly grouped' => $rs->search_rs({}, { distinct => 1 }),
  };

  for my $type (keys %$rstypes) {
    is ($rstypes->{$type}->count, 4, "correct cd count with $type column");

    is_deeply (
      [ $rstypes->{$type}->get_column ('year')->all ],
      [qw(1997 1998 1999 2001)],
      "Getting $type column works",
    );
  }

  # Why do we test this - we want to make sure that the selector *will* actually make
  # it to the group_by as per the distinct => 1 contract. Before 0.08251 this situation
  # would silently drop the group_by entirely, likely ending up with nonsensival results
  # With the current behavior the user will at least get a nice fat exception from the
  # RDBMS (or maybe the RDBMS will even decide to handle the situation sensibly...)
  for (
    [ cnt => 'COUNT( me.cdid )' ],
    [ year_plus_one => 'year + ?' => [ {} => 1 ] ],
  ) {
    my ($col, $sel_grp_sql, @sel_grp_bind) = @$_;

    warnings_exist { is_same_sql_bind(
      $rstypes->{'implicitly grouped'}->get_column($col)->as_query,
      "(
        SELECT $sel_grp_sql
          FROM cd me
          JOIN artist artist
            ON artist.artistid = me.artist
          LEFT JOIN track tracks
            ON tracks.cd = me.cdid
        WHERE artist.name != ? AND tracks.trackid IS NOT NULL
        GROUP BY $sel_grp_sql
        ORDER BY MIN(me.year)
      )",
      [
        @sel_grp_bind,
        [ { dbic_colname => 'artist.name', sqlt_datatype => 'varchar', sqlt_size => 100 }
          => 'evancarrol' ],
        @sel_grp_bind,
      ],
      'Expected (though nonsensical) SQL generated on rscol-with-distinct-over-function',
    ) } qr/
      \QUse of distinct => 1 while selecting anything other than a column \E
      \Qdeclared on the primary ResultSource is deprecated (you selected '$col')\E
    /x, 'deprecation warning';
  }

  {
    local $TODO = 'multiplying join leaks through to the count aggregate... this may never actually work';
    is_deeply (
      [ $rstypes->{'explicitly grouped'}->get_column ('cnt')->all ],
      [qw(1 1 1 2)],
      "Get aggregate over group works",
    );
  }
}

done_testing;
