use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest ':DiffSQL';
use DBIx::Class::_Util 'sigwarn_silencer';

use DBIx::Class::SQLMaker;
my $sa = DBIx::Class::SQLMaker->new;

$SIG{__WARN__} = sigwarn_silencer( qr/\Q{from} structures with conditions not conforming to the SQL::Abstract::Classic syntax are deprecated/ );

my @j = (
    { child => 'person' },
    [ { father => 'person' }, { 'father.person_id' => 'child.father_id' }, ],
    [ { mother => 'person' }, { 'mother.person_id' => 'child.mother_id' } ],
);
my $match = 'person child JOIN person father ON ( father.person_id = '
          . 'child.father_id ) JOIN person mother ON ( mother.person_id '
          . '= child.mother_id )'
          ;
is_same_sql(
  $sa->_recurse_from(@j),
  $match,
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
is_same_sql(
  $sa->_recurse_from(@j2),
  $match,
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

is_same_sql(
  $sa->_recurse_from(@j3),
  $match,
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
is_same_sql(
  $sa->_recurse_from(@j4),
  $match,
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
is_same_sql(
  $sa->_recurse_from(@j5),
  $match,
  'join 5 (SCALAR reference for ON statement) ok'
);

done_testing;
