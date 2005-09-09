use strict;
use Test::More;

BEGIN {
    eval "use DBD::SQLite";
    plan $@
        ? ( skip_all => 'needs DBD::SQLite for testing' )
        : ( tests => 17 );
}

use lib qw(t/lib);

use_ok('DBICTest');

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
my $match = 'person child INNER JOIN person father ON ( father.person_id = '
          . 'child.father_id ) INNER JOIN person mother ON ( mother.person_id '
          . '= child.mother_id )'
          ;

is( $sa->_recurse_from(@j3), $match, 'join 3 (inner join) ok');

my $rs = DBICTest::CD->search(
           { 'year' => 2001, 'artist.name' => 'Caterwauler McCrae' },
           { from => [ { 'me' => 'cd' },
                         [
                           { artist => 'artist' },
                           { 'me.artist' => 'artist.artistid' }
                         ] ] }
         );

cmp_ok( $rs->count, '==', 1, "Single record in resultset");

is($rs->first->title, 'Forkful of bees', 'Correct record returned');

$rs = DBICTest::CD->search(
           { 'year' => 2001, 'artist.name' => 'Caterwauler McCrae' },
           { join => 'artist' });

cmp_ok( $rs->count, '==', 1, "Single record in resultset");

is($rs->first->title, 'Forkful of bees', 'Correct record returned');

$rs = DBICTest::CD->search(
           { 'artist.name' => 'We Are Goth',
             'liner_notes.notes' => 'Kill Yourself!' },
           { join => [ qw/artist liner_notes/ ] });

cmp_ok( $rs->count, '==', 1, "Single record in resultset");

is($rs->first->title, 'Come Be Depressed With Us', 'Correct record returned');

$rs = DBICTest::Artist->search(
        { 'liner_notes.notes' => 'Kill Yourself!' },
        { join => { 'cds' => 'liner_notes' } });

cmp_ok( $rs->count, '==', 1, "Single record in resultset");

is($rs->first->name, 'We Are Goth', 'Correct record returned');

DBICTest::Schema::CD->add_relationship(
    artist => 'DBICTest::Schema::Artist',
    { 'foreign.artistid' => 'self.artist' },
    { accessor => 'filter' },
);

DBICTest::Schema::CD->add_relationship(
    liner_notes => 'DBICTest::Schema::LinerNotes',
    { 'foreign.liner_id' => 'self.cdid' },
    { join_type => 'LEFT', accessor => 'single' });


$rs = DBICTest::CD->search(
           { 'artist.name' => 'Caterwauler McCrae' },
           { prefetch => [ qw/artist liner_notes/ ],
             order_by => 'me.cdid' });

cmp_ok($rs->count, '==', 3, 'Correct number of records returned');

my @cd = $rs->all;

is($cd[0]->title, 'Spoonful of bees', 'First record returned ok');

ok(!exists $cd[0]->{_relationship_data}{liner_notes}, 'No prefetch for NULL LEFT JOIN');

is($cd[1]->{_relationship_data}{liner_notes}->notes, 'Buy Whiskey!', 'Prefetch for present LEFT JOIN');

is($cd[2]->{_inflated_column}{artist}->name, 'Caterwauler McCrae', 'Prefetch on parent object ok');
