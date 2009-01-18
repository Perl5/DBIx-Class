use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;
use Data::Dumper;
use DBIC::SqlMakerTest;

my $schema = DBICTest->init_schema();

my $orig_debug = $schema->storage->debug;

use IO::File;

BEGIN {
    eval "use DBD::SQLite";
    plan $@
        ? ( skip_all => 'needs DBD::SQLite for testing' )
        : ( tests => 16 );
}

# figure out if we've got a version of sqlite that is older than 3.2.6, in
# which case COUNT(DISTINCT()) doesn't work
my $is_broken_sqlite = 0;
my ($sqlite_major_ver,$sqlite_minor_ver,$sqlite_patch_ver) =
    split /\./, $schema->storage->dbh->get_info(18);
if( $schema->storage->dbh->get_info(17) eq 'SQLite' &&
    ( ($sqlite_major_ver < 3) ||
      ($sqlite_major_ver == 3 && $sqlite_minor_ver < 2) ||
      ($sqlite_major_ver == 3 && $sqlite_minor_ver == 2 && $sqlite_patch_ver < 6) ) ) {
    $is_broken_sqlite = 1;
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
is_same_sql_bind(
  $sa->_recurse_from(@j), [],
  $match, [],
  'join 1 ok'
);

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
is_same_sql_bind(
  $sa->_recurse_from(@j2), [],
  $match, [],
  'join 2 ok'
);


my @j3 = (
    { child => 'person' },
    [ { father => 'person', -join_type => 'inner' }, { 'father.person_id' => 'child.father_id' }, ],
    [ { mother => 'person', -join_type => 'inner'  }, { 'mother.person_id' => 'child.mother_id' } ],
);
$match = 'person child INNER JOIN person father ON ( father.person_id = '
          . 'child.father_id ) INNER JOIN person mother ON ( mother.person_id '
          . '= child.mother_id )'
          ;

is_same_sql_bind(
  $sa->_recurse_from(@j3), [],
  $match, [],
  'join 3 (inner join) ok'
);

my @j4 = (
    { mother => 'person' },
    [   [   { child => 'person', -join_type => 'left' },
            [   { father             => 'person', -join_type => 'right' },
                { 'father.person_id' => 'child.father_id' }
            ]
        ],
        { 'mother.person_id' => 'child.mother_id' }
    ],
);
$match = 'person mother LEFT JOIN (person child RIGHT JOIN person father ON ('
       . ' father.person_id = child.father_id )) ON ( mother.person_id = '
       . 'child.mother_id )'
       ;
is_same_sql_bind(
  $sa->_recurse_from(@j4), [],
  $match, [],
  'join 4 (nested joins + join types) ok'
);

my @j5 = (
    { child => 'person' },
    [ { father => 'person' }, { 'father.person_id' => \'!= child.father_id' }, ],
    [ { mother => 'person' }, { 'mother.person_id' => 'child.mother_id' } ],
);
$match = 'person child JOIN person father ON ( father.person_id != '
          . 'child.father_id ) JOIN person mother ON ( mother.person_id '
          . '= child.mother_id )'
          ;
is_same_sql_bind(
  $sa->_recurse_from(@j5), [],
  $match, [],
  'join 5 (SCALAR reference for ON statement) ok'
);

my @j6 = (
    { child => 'person' },
    [ { father => 'person' }, { 'father.person_id' => { '!=', '42' } }, ],
    [ { mother => 'person' }, { 'mother.person_id' => 'child.mother_id' } ],
);
$match = qr/^HASH reference arguments are not supported in JOINS - try using "\.\.\." instead/;
eval { $sa->_recurse_from(@j6) };
like( $@, $match, 'join 6 (HASH reference for ON statement dies) ok' );

my $rs = $schema->resultset("CD")->search(
           { 'year' => 2001, 'artist.name' => 'Caterwauler McCrae' },
           { from => [ { 'me' => 'cd' },
                         [
                           { artist => 'artist' },
                           { 'me.artist' => 'artist.artistid' }
                         ] ] }
         );

cmp_ok( $rs + 0, '==', 1, "Single record in resultset");

is($rs->first->title, 'Forkful of bees', 'Correct record returned');

$rs = $schema->resultset("CD")->search(
           { 'year' => 2001, 'artist.name' => 'Caterwauler McCrae' },
           { join => 'artist' });

cmp_ok( $rs + 0, '==', 1, "Single record in resultset");

is($rs->first->title, 'Forkful of bees', 'Correct record returned');

$rs = $schema->resultset("CD")->search(
           { 'artist.name' => 'We Are Goth',
             'liner_notes.notes' => 'Kill Yourself!' },
           { join => [ qw/artist liner_notes/ ] });

cmp_ok( $rs + 0, '==', 1, "Single record in resultset");

is($rs->first->title, 'Come Be Depressed With Us', 'Correct record returned');

# when using join attribute, make sure slice()ing all objects has same count as all()
$rs = $schema->resultset("CD")->search(
    { 'artist' => 1 },
    { join => [qw/artist/], order_by => 'artist.name' }
);
cmp_ok( scalar $rs->all, '==', scalar $rs->slice(0, $rs->count - 1), 'slice() with join has same count as all()' );

ok(!$rs->slice($rs->count+1000, $rs->count+1002)->count,
  'Slicing beyond end of rs returns a zero count');

$rs = $schema->resultset("Artist")->search(
        { 'liner_notes.notes' => 'Kill Yourself!' },
        { join => { 'cds' => 'liner_notes' } });

cmp_ok( $rs->count, '==', 1, "Single record in resultset");

is($rs->first->name, 'We Are Goth', 'Correct record returned');

