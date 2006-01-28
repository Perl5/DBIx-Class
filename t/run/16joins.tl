sub run_tests {
my $schema = shift;

use IO::File;

BEGIN {
    eval "use DBD::SQLite";
    plan $@
        ? ( skip_all => 'needs DBD::SQLite for testing' )
        : ( tests => 31 );
}

# test the abstract join => SQL generator
my $sa = new DBIC::SQL::Abstract;

my @j = (
    { child => 'person' },
    [ { father => 'person' }, { 'father.person_id' => 'child.father_id' }, ],
    [ { mother => 'person' }, { 'mother.person_id' => 'child.mother_id' } ],
);
my $match = 'person child JOIN person father ON ( father.person_id = '
          . 'child.father_id ) JOIN person mother ON ( mother.person_id '
          . '= child.mother_id )'
          ;
is( $sa->_recurse_from(@j), $match, 'join 1 ok' );

my @j2 = (
    { mother => 'person' },
    [   [   { child => 'person' },
            [   { father             => 'person' },
                { 'father.person_id' => 'child.father_id' }
            ]
        ],
        { 'mother.person_id' => 'child.mother_id' }
    ],
);
$match = 'person mother JOIN (person child JOIN person father ON ('
       . ' father.person_id = child.father_id )) ON ( mother.person_id = '
       . 'child.mother_id )'
       ;
is( $sa->_recurse_from(@j2), $match, 'join 2 ok' );

my @j3 = (
    { child => 'person' },
    [ { father => 'person', -join_type => 'inner' }, { 'father.person_id' => 'child.father_id' }, ],
    [ { mother => 'person', -join_type => 'inner'  }, { 'mother.person_id' => 'child.mother_id' } ],
);
$match = 'person child INNER JOIN person father ON ( father.person_id = '
          . 'child.father_id ) INNER JOIN person mother ON ( mother.person_id '
          . '= child.mother_id )'
          ;

is( $sa->_recurse_from(@j3), $match, 'join 3 (inner join) ok');

my $rs = $schema->resultset("CD")->search(
           { 'year' => 2001, 'artist.name' => 'Caterwauler McCrae' },
           { from => [ { 'me' => 'cd' },
                         [
                           { artist => 'artist' },
                           { 'me.artist' => 'artist.artistid' }
                         ] ] }
         );

cmp_ok( $rs->count, '==', 1, "Single record in resultset");

is($rs->first->title, 'Forkful of bees', 'Correct record returned');

$rs = $schema->resultset("CD")->search(
           { 'year' => 2001, 'artist.name' => 'Caterwauler McCrae' },
           { join => 'artist' });

cmp_ok( $rs->count, '==', 1, "Single record in resultset");

is($rs->first->title, 'Forkful of bees', 'Correct record returned');

$rs = $schema->resultset("CD")->search(
           { 'artist.name' => 'We Are Goth',
             'liner_notes.notes' => 'Kill Yourself!' },
           { join => [ qw/artist liner_notes/ ] });

cmp_ok( $rs->count, '==', 1, "Single record in resultset");

is($rs->first->title, 'Come Be Depressed With Us', 'Correct record returned');

# when using join attribute, make sure slice()ing all objects has same count as all()
$rs = $schema->resultset("CD")->search(
    { 'artist' => 1 },
    { join => [qw/artist/], order_by => 'artist.name' }
);
cmp_ok( scalar $rs->all, '==', scalar $rs->slice(0, $rs->count - 1), 'slice() with join has same count as all()' );

$rs = $schema->resultset("Artist")->search(
        { 'liner_notes.notes' => 'Kill Yourself!' },
        { join => { 'cds' => 'liner_notes' } });

cmp_ok( $rs->count, '==', 1, "Single record in resultset");

is($rs->first->name, 'We Are Goth', 'Correct record returned');

$rs = $schema->resultset("CD")->search(
           { 'artist.name' => 'Caterwauler McCrae' },
           { prefetch => [ qw/artist liner_notes/ ],
             order_by => 'me.cdid' });

cmp_ok($rs->count, '==', 3, 'Correct number of records returned');

# start test for prefetch SELECT count
unlink 't/var/dbic.trace' if -e 't/var/dbic.trace';
DBI->trace(1, 't/var/dbic.trace');

my @cd = $rs->all;

is($cd[0]->title, 'Spoonful of bees', 'First record returned ok');

ok(!defined $cd[0]->liner_notes, 'No prefetch for NULL LEFT join');

is($cd[1]->{_relationship_data}{liner_notes}->notes, 'Buy Whiskey!', 'Prefetch for present LEFT JOIN');

is(ref $cd[1]->liner_notes, 'DBICTest::LinerNotes', 'Prefetch returns correct class');

is($cd[2]->{_inflated_column}{artist}->name, 'Caterwauler McCrae', 'Prefetch on parent object ok');

# count the SELECTs
DBI->trace(0, undef);
my $selects = 0;
my $trace = IO::File->new('t/var/dbic.trace', '<') 
    or die "Unable to read trace file";
while (<$trace>) {
    $selects++ if /SELECT/;
}
$trace->close;
unlink 't/var/dbic.trace';
is($selects, 1, 'prefetch ran only 1 select statement');

# start test for nested prefetch SELECT count
unlink 't/var/dbic.trace' if -e 't/var/dbic.trace';
DBI->trace(1, 't/var/dbic.trace');

$rs = $schema->resultset('Tag')->search(
  {},
  {
    prefetch => { cd => 'artist' }
  }
);

my $tag = $rs->first;

is( $tag->cd->title, 'Spoonful of bees', 'step 1 ok for nested prefetch' );

is( $tag->cd->artist->name, 'Caterwauler McCrae', 'step 2 ok for nested prefetch');

# count the SELECTs
DBI->trace(0, undef);
$selects = 0;
$trace = IO::File->new('t/var/dbic.trace', '<') 
    or die "Unable to read trace file";
while (<$trace>) {
    $selects++ if /SELECT(?!.*WHERE 1=0.*)/;
}
$trace->close;
unlink 't/var/dbic.trace';
is($selects, 1, 'nested prefetch ran exactly 1 select statement (excluding column_info)');

$rs = $schema->resultset('Tag')->search(
  {},
  {
    join => { cd => 'artist' },
    prefetch => { cd => 'artist' }
  }
);

cmp_ok( $rs->count, '>=', 0, 'nested prefetch does not duplicate joins' );

my ($artist) = $schema->resultset("Artist")->search({ 'cds.year' => 2001 },
                 { order_by => 'artistid DESC', join => 'cds' });

is($artist->name, 'Random Boy Band', "Join search by object ok");

my @cds = $schema->resultset("CD")->search({ 'liner_notes.notes' => 'Buy Merch!' },
                               { join => 'liner_notes' });

cmp_ok(scalar @cds, '==', 1, "Single CD retrieved via might_have");

is($cds[0]->title, "Generic Manufactured Singles", "Correct CD retrieved");

my @artists = $schema->resultset("Artist")->search({ 'tags.tag' => 'Shiny' },
                                       { join => { 'cds' => 'tags' } });

cmp_ok( @artists, '==', 2, "two-join search ok" );

$rs = $schema->resultset("CD")->search(
  {},
  { group_by => [qw/ title me.cdid /] }
);

cmp_ok( $rs->count, '==', 5, "count() ok after group_by on main pk" );

cmp_ok( scalar $rs->all, '==', 5, "all() returns same count as count() after group_by on main pk" );

$rs = $schema->resultset("CD")->search(
  {},
  { join => [qw/ artist /], group_by => [qw/ artist.name /] }
);

cmp_ok( $rs->count, '==', 3, "count() ok after group_by on related column" );

cmp_ok( scalar $rs->all, '==', 3, "all() returns same count as count() after group_by on related column" );
}

1;
