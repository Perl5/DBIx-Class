use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest ':DiffSQL';

my $schema = DBICTest->init_schema();

my $rs = $schema->resultset("CD")->search(
           { 'year' => 2001, 'artist.name' => 'Caterwauler McCrae' },
           { from => [
              { 'me' => 'cd' },
              [
                { artist => 'artist' },
                { 'me.artist' => { -ident => 'artist.artistid' } },
              ],
           ] }
         );

is( $rs + 0, 1, "Single record in resultset");

is($rs->first->title, 'Forkful of bees', 'Correct record returned');

$rs = $schema->resultset("CD")->search(
           { 'year' => 2001, 'artist.name' => 'Caterwauler McCrae' },
           { join => 'artist' });

is( $rs + 0, 1, "Single record in resultset");

is($rs->first->title, 'Forkful of bees', 'Correct record returned');

$rs = $schema->resultset("CD")->search(
           { 'artist.name' => 'We Are Goth',
             'liner_notes.notes' => 'Kill Yourself!' },
           { join => [ qw/artist liner_notes/ ] });

is( $rs + 0, 1, "Single record in resultset");

is($rs->first->title, 'Come Be Depressed With Us', 'Correct record returned');

# when using join attribute, make sure slice()ing all objects has same count as all()
$rs = $schema->resultset("CD")->search(
    { 'artist' => 1 },
    { join => [qw/artist/], order_by => 'artist.name' }
);
is( scalar $rs->all, scalar $rs->slice(0, $rs->count - 1), 'slice() with join has same count as all()' );

ok(!$rs->slice($rs->count+1000, $rs->count+1002)->count,
  'Slicing beyond end of rs returns a zero count');

$rs = $schema->resultset("Artist")->search(
        { 'liner_notes.notes' => 'Kill Yourself!' },
        { join => { 'cds' => 'liner_notes' } });

is( $rs->count, 1, "Single record in resultset");

is($rs->first->name, 'We Are Goth', 'Correct record returned');


{
    $schema->populate('Artist', [
        [ qw/artistid name/ ],
        [ 4, 'Another Boy Band' ],
    ]);
    $schema->populate('CD', [
        [ qw/cdid artist title year/ ],
        [ 6, 2, "Greatest Hits", 2001 ],
        [ 7, 4, "Greatest Hits", 2005 ],
        [ 8, 4, "BoyBandBlues", 2008 ],
    ]);
    $schema->populate('TwoKeys', [
        [ qw/artist cd/ ],
        [ 2, 4 ],
        [ 2, 6 ],
        [ 4, 7 ],
        [ 4, 8 ],
    ]);

    my $cd_count = sub { $schema->resultset("CD")->count };
    my $tk_count = sub { $schema->resultset("TwoKeys")->count };

    is($cd_count->(), 8, '8 rows in table cd');
    is($tk_count->(), 7, '7 rows in table twokeys');

    my $artist1_rs = $schema->resultset("CD")->search(
      { 'artist.name' => 'Caterwauler McCrae' },
      { join => [qw/artist/]}
    );

    my $artist2_rs = $schema->resultset("CD")->search(
      { 'artist.name' => 'Random Boy Band' },
      { join => [qw/artist/]}
    );

    is( $artist1_rs->count, 3, '3 Caterwauler McCrae CDs' );
    ok( $artist1_rs->delete, 'Successfully deleted 3 CDs' );
    is( $artist1_rs->count, 0, '0 Caterwauler McCrae CDs' );
    is( $artist2_rs->count, 2, '3 Random Boy Band CDs' );
    ok( $artist2_rs->update( { 'artist' => 1 } ) );
    is( $artist2_rs->count, 0, '0 Random Boy Band CDs' );
    is( $artist1_rs->count, 2, '2 Caterwauler McCrae CDs' );

    # test update on multi-column-pk
    my $tk1_rs = $schema->resultset("TwoKeys")->search(
      {
        'artist.name' => { like => '%Boy Band' },
        'cd.title'    => 'Greatest Hits',
      },
      { join => [qw/artist cd/] }
    );

    my $tk2_rs = $schema->resultset("TwoKeys")->search(
      { 'artist.name' => 'Caterwauler McCrae' },
      { join => [qw/artist/]}
    );

    is( $tk2_rs->count, 2, 'TwoKeys count == 2' );
    is( $tk1_rs->count, 2, 'TwoKeys count == 2' );
    ok( $tk1_rs->update( { artist => 1 } ) );
    is( $tk1_rs->count, 0, 'TwoKeys count == 0' );
    is( $tk2_rs->count, 4, '2 Caterwauler McCrae CDs' );
    ok( $tk2_rs->delete, 'Successfully deleted 4 CDs' );
    is($cd_count->(), 5, '5 rows in table cd');
    is($tk_count->(), 3, '3 rows in table twokeys');
}

done_testing;
