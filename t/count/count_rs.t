use strict;
use warnings;

use lib qw(t/lib);

use Test::More;
use DBICTest ':DiffSQL';

my ($ROWS, $OFFSET) = (
   DBIx::Class::SQLMaker::ClassicExtensions->__rows_bindtype,
   DBIx::Class::SQLMaker::ClassicExtensions->__offset_bindtype,
);

my $schema = DBICTest->init_schema();

# non-collapsing prefetch (no multi prefetches)
{
  my $rs = $schema->resultset("CD")
            ->search_related('tracks',
                { position => [1,2] },
                { prefetch => [qw/disc lyrics/], rows => 3, offset => 8 },
            );
  my @wherebind = (
    [ { sqlt_datatype => 'int', dbic_colname => 'position' }
      => 1 ],
    [ { sqlt_datatype => 'int', dbic_colname => 'position' }
      => 2 ],
  );

  is ($rs->all, 2, 'Correct number of objects');

  $schema->is_executed_sql_bind( sub {
    is ($rs->count, 2, 'Correct count via count()');
  }, [[
    'SELECT COUNT( * )
      FROM cd me
      JOIN track tracks ON tracks.cd = me.cdid
      JOIN cd disc ON disc.cdid = tracks.cd
     WHERE ( ( position = ? OR position = ? ) )
    ', @wherebind
  ]], 'count softlimit applied');

  my $crs = $rs->count_rs;
  is ($crs->next, 2, 'Correct count via count_rs()');

  is_same_sql_bind (
    $crs->as_query,
    '(SELECT COUNT( * )
       FROM (
        SELECT tracks.trackid
          FROM cd me
          JOIN track tracks ON tracks.cd = me.cdid
          JOIN cd disc ON disc.cdid = tracks.cd
        WHERE ( ( position = ? OR position = ? ) )
        LIMIT ? OFFSET ?
       ) tracks
    )',
    [ @wherebind, [$ROWS => 3], [$OFFSET => 8] ],
    'count_rs db-side limit applied',
  );
}

# has_many prefetch with limit
{
  my $rs = $schema->resultset("Artist")
            ->search_related('cds',
                { 'tracks.position' => [1,2] },
                { prefetch => [qw/tracks artist/], rows => 3, offset => 4 },
            );
  my @wherebind = (
    [ { sqlt_datatype => 'int', dbic_colname => 'tracks.position' }
      => 1 ],
    [ { sqlt_datatype => 'int', dbic_colname => 'tracks.position' }
      => 2 ],
  );

  is ($rs->all, 1, 'Correct number of objects');

  $schema->is_executed_sql_bind( sub {
    is ($rs->count, 1, 'Correct count via count()');
  }, [ [
    'SELECT COUNT( * )
      FROM (
        SELECT cds.cdid
          FROM artist me
          JOIN cd cds ON cds.artist = me.artistid
          LEFT JOIN track tracks ON tracks.cd = cds.cdid
          JOIN artist artist ON artist.artistid = cds.artist
        WHERE tracks.position = ? OR tracks.position = ?
        GROUP BY cds.cdid
      ) cds
    ', @wherebind
  ]], 'count softlimit applied' );

  my $crs = $rs->count_rs;
  is ($crs->next, 1, 'Correct count via count_rs()');

  is_same_sql_bind (
    $crs->as_query,
    '(SELECT COUNT( * )
      FROM (
        SELECT cds.cdid
          FROM artist me
          JOIN cd cds ON cds.artist = me.artistid
          LEFT JOIN track tracks ON tracks.cd = cds.cdid
          JOIN artist artist ON artist.artistid = cds.artist
        WHERE tracks.position = ? OR tracks.position = ?
        GROUP BY cds.cdid
        LIMIT ? OFFSET ?
      ) cds
    )',
    [ @wherebind, [$ROWS => 3], [$OFFSET => 4], ],
    'count_rs db-side limit applied',
  );
}

# count with a having clause
{
  my $rs = $schema->resultset("Artist")->search(
    {},
    {
      join      => 'cds',
      group_by  => 'me.artistid',
      '+select' => [ { max => 'cds.year', -as => 'newest_cd_year' } ],
      '+as'     => ['newest_cd_year'],
      having    => { 'newest_cd_year' => '2001' }
    }
  );

  my $crs = $rs->count_rs;

  is_same_sql_bind (
    $crs->as_query,
    '(SELECT COUNT( * )
      FROM (
        SELECT me.artistid, MAX( cds.year ) AS newest_cd_year
          FROM artist me
          LEFT JOIN cd cds ON cds.artist = me.artistid
        GROUP BY me.artistid
        HAVING newest_cd_year = ?
      ) me
    )',
    [ [ { dbic_colname => 'newest_cd_year' }
          => '2001' ] ],
    'count with having clause keeps sql as alias',
  );

  is ($crs->next, 2, 'Correct artist count (each with one 2001 cd)');
}

# count with two having clauses
{
  my $rs = $schema->resultset("Artist")->search(
    {},
    {
      join      => 'cds',
      group_by  => 'me.artistid',
      '+select' => [ { max => 'cds.year', -as => 'newest_cd_year' } ],
      '+as'     => ['newest_cd_year'],
      having    => { 'newest_cd_year' => [ '1998', '2001' ] }
    }
  );

  my $crs = $rs->count_rs;

  is_same_sql_bind (
    $crs->as_query,
    '(SELECT COUNT( * )
      FROM (
        SELECT me.artistid, MAX( cds.year ) AS newest_cd_year
          FROM artist me
          LEFT JOIN cd cds ON cds.artist = me.artistid
        GROUP BY me.artistid
        HAVING newest_cd_year = ? OR newest_cd_year = ?
      ) me
    )',
    [
      [ { dbic_colname => 'newest_cd_year' }
          => '1998' ],
      [ { dbic_colname => 'newest_cd_year' }
          => '2001' ],
    ],
    'count with having clause keeps sql as alias',
  );

  is ($crs->next, 3, 'Correct artist count (each with one 1998 or 2001 cd)');
}

done_testing;
