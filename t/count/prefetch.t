use strict;
use warnings;

use lib qw(t/lib);

use Test::More;
use DBICTest;
use DBIC::SqlMakerTest;
use DBIC::DebugObj;

plan tests => 17;

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
    'SELECT COUNT( * ) FROM (SELECT cds.cdid FROM artist me JOIN cd cds ON cds.artist = me.artistid LEFT JOIN track tracks ON tracks.cd = cds.cdid JOIN artist artist ON artist.artistid = cds.artist WHERE tracks.position = ? OR tracks.position = ? GROUP BY cds.cdid) count_subq',
    [ qw/'1' '2'/ ],
  );
}

# Added test by mo per http://scsys.co.uk:8001/31870
TODO: {
  todo_skip "This breaks stuff", 3;
  my $rs = $schema->resultset("Artist")->search(undef, {distinct => 1})
            ->search_related('cds')->search_related('genre',
                { 'genre.name' => 'foo' },
                { prefetch => q(cds) },
            );
  is ($rs->all, 5, 'Correct number of objects');


  my ($sql, @bind);
  $schema->storage->debugobj(DBIC::DebugObj->new(\$sql, \@bind));
  $schema->storage->debug(1);


  is ($rs->count, 5, 'Correct count');

  is_same_sql_bind (
    $sql,
    \@bind,
    'SELECT COUNT( * ) FROM (SELECT cds.cdid FROM artist me JOIN cd cds ON cds.artist = me.artistid LEFT JOIN track tracks ON tracks.cd = cds.cdid JOIN artist artist ON artist.artistid = cds.artist WHERE tracks.position = ? OR tracks.position = ? GROUP BY cds.cdid) count_subq',
    [ qw/'1' '2'/ ],
  );
}

# collapsing prefetch with distinct
TODO: {
  todo_skip "This is busted", 3;
  my $rs = $schema->resultset("Artist")->search(undef, {distinct => 1})
            ->search_related('cds')->search_related('genre',
                { 'genre.name' => 'foo' },
                { prefetch => q(cds) },
            );
  is ($rs->all, 5, 'Correct number of objects');


  my ($sql, @bind);
  $schema->storage->debugobj(DBIC::DebugObj->new(\$sql, \@bind));
  $schema->storage->debug(1);


  is ($rs->count, 5, 'Correct count');

  is_same_sql_bind (
    $sql,
    \@bind,
    'SELECT COUNT( * ) FROM (SELECT cds.cdid FROM artist me JOIN cd cds ON cds.artist = me.artistid LEFT JOIN track tracks ON tracks.cd = cds.cdid JOIN artist artist ON artist.artistid = cds.artist WHERE tracks.position = ? OR tracks.position = ? GROUP BY cds.cdid) count_subq',
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
    'SELECT COUNT( * ) FROM cd me JOIN track tracks ON tracks.cd = me.cdid JOIN cd disc ON disc.cdid = tracks.cd LEFT JOIN lyrics lyrics ON lyrics.track_id = tracks.trackid WHERE ( ( position = ? OR position = ? ) )',
    [ qw/'1' '2'/ ],
  );
}

# Added test by mo per http://scsys.co.uk:8001/31873
TODO: {
    todo_skip "This breaks stuff", 5;
    my $rs = $schema->resultset("Artwork")->search(undef, {distinct => 1})
              ->search_related('artwork_to_artist')->search_related('artist',
                 undef,
                  { prefetch => q(cds) },
              );
    is($rs->all, 0, 'failure without WHERE');

    $rs = $schema->resultset("Artwork")->search(undef, {distinct => 1})
              ->search_related('artwork_to_artist')->search_related('artist',
                 { 'cds.title' => 'foo' }, # this line has changed
                  { prefetch => q(cds) },
              );
    is($rs->all, 0, 'success with WHERE');
    
    # different case
    
    $rs = $schema->resultset("Artist")->search(undef)#, {distinct => 1})
                ->search_related('cds')->search_related('genre',
                    { 'genre.name' => 'foo' },
                    { prefetch => q(cds) },
                 );
    is($rs->all, 0, 'success without distinct');
    
    $rs = $schema->resultset("Artist")->search(undef, {distinct => 1})
                ->search_related('cds')->search_related('genre',
                    { 'genre.name' => 'foo' },
                    #{ prefetch => q(cds) },
                 );
    is($rs->all, 0, 'success without prefetch');

    $rs = $schema->resultset("Artist")->search(undef, {distinct => 1})
                ->search_related('cds')->search_related('genre',
                    { 'genre.name' => 'foo' },
                    { prefetch => q(cds) },
                 );
    is($rs->all, 0, 'failure with distinct');
}
