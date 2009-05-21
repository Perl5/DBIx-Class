use strict;
use warnings;

use lib qw(t/lib);

use Test::More;
use DBICTest;
use DBIC::SqlMakerTest;
use DBIC::DebugObj;

plan tests => 6;

my $schema = DBICTest->init_schema();

# collapsing prefetch
{
  my $rs = $schema->resultset("Artist")
            ->search_related('cds',
                { 'tracks.position' => [1,2] },
                { prefetch => [qw/tracks artist/] },
            );
  is ($rs->all, 5, 'Correct number of objects');


  my ($sql, @bind);
  $schema->storage->debugobj(DBIC::DebugObj->new(\$sql, \@bind));
  $schema->storage->debug(1);


  is ($rs->count, 5, 'Correct count');

  is_same_sql_bind (
    $sql,
    \@bind,
    'SELECT COUNT( * ) FROM (SELECT cds.cdid FROM artist me LEFT JOIN cd cds ON cds.artist = me.artistid LEFT JOIN track tracks ON tracks.cd = cds.cdid JOIN artist artist ON artist.artistid = cds.artist WHERE tracks.position = ? OR tracks.position = ? GROUP BY cds.cdid) count_subq',
    [ qw/'1' '2'/ ],
  );
}

# non-collapsing prefetch (no multi prefetches)
{
  my $rs = $schema->resultset("CD")
            ->search_related('tracks',
                { position => [1,2] },
                { prefetch => [qw/disc lyrics/] },
            );
  is ($rs->all, 10, 'Correct number of objects');


  my ($sql, @bind);
  $schema->storage->debugobj(DBIC::DebugObj->new(\$sql, \@bind));
  $schema->storage->debug(1);


  is ($rs->count, 10, 'Correct count');

  is_same_sql_bind (
    $sql,
    \@bind,
    'SELECT COUNT( * ) FROM cd me LEFT JOIN track tracks ON tracks.cd = me.cdid JOIN cd disc ON disc.cdid = tracks.cd LEFT JOIN lyrics lyrics ON lyrics.track_id = tracks.trackid WHERE ( ( position = ? OR position = ? ) )',
    [ qw/'1' '2'/ ],
  );
}
