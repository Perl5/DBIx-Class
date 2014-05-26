use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBICTest ':DiffSQL';

my $schema = DBICTest->init_schema();

# make sure order + distinct do not double-inject group criteria
my $rs = $schema->resultset ('CD')->search ({}, {
  distinct => 1,
  columns => 'title',
});

# title + cdid == unique constraint
my $unique_rs = $rs->search ({}, {
  '+columns' => 'cdid',
});

is_same_sql_bind (
  $rs->search({}, { order_by => 'title' })->as_query,
  '(
    SELECT me.title
      FROM cd me
    GROUP BY me.title
    ORDER BY title
  )',
  [],
  'Correct GROUP BY on selection+order_by on same column',
);

is_same_sql_bind (
  $rs->search({}, { order_by => 'year' })->as_query,
  '(
    SELECT me.title
      FROM cd me
    GROUP BY me.title
    ORDER BY MIN(year)
  )',
  [],
  'Correct GROUP BY on non-unique selection and order by a different column',
);

is_same_sql_bind (
  $unique_rs->search({}, { order_by => 'year' })->as_query,
  '(
    SELECT me.title, me.cdid
      FROM cd me
    GROUP BY me.title, me.cdid, me.year
    ORDER BY year
  )',
  [],
  'Correct GROUP BY on unique selection and order by a different column',
);

is_same_sql_bind (
  $rs->search({}, { order_by => 'artist.name', join => 'artist'  })->as_query,
  '(
    SELECT me.title
      FROM cd me
      JOIN artist artist
        ON artist.artistid = me.artist
    GROUP BY me.title
    ORDER BY MIN(artist.name)
  )',
  [],
  'Correct GROUP BY on non-unique selection and external single order_by',
);

is_same_sql_bind (
  $unique_rs->search({}, { order_by => 'artist.name', join => 'artist'  })->as_query,
  '(
    SELECT me.title, me.cdid
      FROM cd me
      JOIN artist artist
        ON artist.artistid = me.artist
    GROUP BY me.title, me.cdid, artist.name
    ORDER BY artist.name
  )',
  [],
  'Correct GROUP BY on unique selection and external single order_by',
);

is_same_sql_bind (
  $rs->search({}, { order_by => 'tracks.title', join => 'tracks'  })->as_query,
  '(
    SELECT me.title
      FROM cd me
      LEFT JOIN track tracks
        ON tracks.cd = me.cdid
    GROUP BY me.title
    ORDER BY MIN(tracks.title)
  )',
  [],
  'Correct GROUP BY on non-unique selection and external multi order_by',
);

is_same_sql_bind (
  $unique_rs->search({}, { order_by => 'tracks.title', join => 'tracks'  })->as_query,
  '(
    SELECT me.title, me.cdid
      FROM cd me
      LEFT JOIN track tracks
        ON tracks.cd = me.cdid
    GROUP BY me.title, me.cdid
    ORDER BY MIN(tracks.title)
  )',
  [],
  'Correct GROUP BY on unique selection and external multi order_by',
);

done_testing;
