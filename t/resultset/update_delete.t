use strict;
use warnings;

use lib qw(t/lib);
use Test::More;
use Test::Exception;

use DBICTest::Schema::CD;
BEGIN {
  # the default scalarref table name will not work well for this test
  DBICTest::Schema::CD->table('cd');
}

use DBICTest;
use DBIC::DebugObj;
use DBIC::SqlMakerTest;

my $schema = DBICTest->init_schema;

my ($sql, @bind);
my $debugobj = DBIC::DebugObj->new (\$sql, \@bind);
my $orig_debugobj = $schema->storage->debugobj;
my $orig_debug = $schema->storage->debug;

my $tkfks = $schema->resultset('FourKeys_to_TwoKeys');

my ($fa, $fb, $fc) = $tkfks->related_resultset ('fourkeys')->populate ([
  [qw/foo bar hello goodbye sensors read_count/],
  [qw/1   1   1     1       a       10         /],
  [qw/2   2   2     2       b       20         /],
  [qw/1   1   1     2       c       30         /],
]);

# This is already provided by DBICTest
#my ($ta, $tb) = $tkfk->related_resultset ('twokeys')->populate ([
#  [qw/artist  cd /],
#  [qw/1       1  /],
#  [qw/2       2  /],
#]);
my ($ta, $tb) = $schema->resultset ('TwoKeys')
                  ->search ( [ { artist => 1, cd => 1 }, { artist => 2, cd => 2 } ])
                    ->all;

my $tkfk_cnt = $tkfks->count;

my $non_void_ctx = $tkfks->populate ([
  { autopilot => 'a', fourkeys =>  $fa, twokeys => $ta, pilot_sequence => 10 },
  { autopilot => 'b', fourkeys =>  $fb, twokeys => $tb, pilot_sequence => 20 },
  { autopilot => 'x', fourkeys =>  $fa, twokeys => $tb, pilot_sequence => 30 },
  { autopilot => 'y', fourkeys =>  $fb, twokeys => $ta, pilot_sequence => 40 },
]);
is ($tkfks->count, $tkfk_cnt += 4, 'FourKeys_to_TwoKeys populated succesfully');

#
# Make sure the forced group by works (i.e. the joining does not cause double-updates)
#

# create a resultset matching $fa and $fb only
my $fks = $schema->resultset ('FourKeys')->search (
  {
    sensors => { '!=', 'c' },
    ( map { $_ => [1, 2] } qw/foo bar hello goodbye/ ),
  }, { join => { fourkeys_to_twokeys => 'twokeys' }}
);

is ($fks->count, 4, 'Joined FourKey count correct (2x2)');

$schema->storage->debugobj ($debugobj);
$schema->storage->debug (1);
$fks->update ({ read_count => \ 'read_count + 1' });
$schema->storage->debugobj ($orig_debugobj);
$schema->storage->debug ($orig_debug);

is_same_sql_bind (
  $sql,
  \@bind,
  'UPDATE fourkeys
   SET read_count = read_count + 1
   WHERE ( ( ( bar = ? OR bar = ? ) AND ( foo = ? OR foo = ? ) AND ( goodbye = ? OR goodbye = ? ) AND ( hello = ? OR hello = ? ) AND sensors != ? ) )
  ',
  [ ("'1'", "'2'") x 4, "'c'" ],
  'Correct update-SQL with multijoin with pruning',
);

is ($fa->discard_changes->read_count, 11, 'Update ran only once on discard-join resultset');
is ($fb->discard_changes->read_count, 21, 'Update ran only once on discard-join resultset');
is ($fc->discard_changes->read_count, 30, 'Update did not touch outlier');

# make the multi-join stick
my $fks_multi = $fks->search({ 'fourkeys_to_twokeys.pilot_sequence' => { '!=' => 666 } });

$schema->storage->debugobj ($debugobj);
$schema->storage->debug (1);
$fks_multi->update ({ read_count => \ 'read_count + 1' });
$schema->storage->debugobj ($orig_debugobj);
$schema->storage->debug ($orig_debug);

is_same_sql_bind (
  $sql,
  \@bind,
  'UPDATE fourkeys
   SET read_count = read_count + 1
   WHERE ( bar = ? AND foo = ? AND goodbye = ? AND hello = ? ) OR ( bar = ? AND foo = ? AND goodbye = ? AND hello = ? )',
  [ map { "'$_'" } ( (1) x 4, (2) x 4 ) ],
  'Correct update-SQL with multijoin without pruning',
);

is ($fa->discard_changes->read_count, 12, 'Update ran only once on joined resultset');
is ($fb->discard_changes->read_count, 22, 'Update ran only once on joined resultset');
is ($fc->discard_changes->read_count, 30, 'Update did not touch outlier');

# try the same sql with forced multicolumn in
$schema->storage->_use_multicolumn_in (1);
$schema->storage->debugobj ($debugobj);
$schema->storage->debug (1);
throws_ok { $fks_multi->update ({ read_count => \ 'read_count + 1' }) } # this can't actually execute, we just need the "as_query"
  qr/\QDBI Exception:/ or do { $sql = ''; @bind = () };
$schema->storage->_use_multicolumn_in (undef);
$schema->storage->debugobj ($orig_debugobj);
$schema->storage->debug ($orig_debug);

is_same_sql_bind (
  $sql,
  \@bind,
  'UPDATE fourkeys
    SET read_count = read_count + 1
    WHERE (
      (foo, bar, hello, goodbye) IN (
        SELECT me.foo, me.bar, me.hello, me.goodbye
          FROM fourkeys me
          LEFT JOIN fourkeys_to_twokeys fourkeys_to_twokeys ON
                fourkeys_to_twokeys.f_bar = me.bar
            AND fourkeys_to_twokeys.f_foo = me.foo
            AND fourkeys_to_twokeys.f_goodbye = me.goodbye
            AND fourkeys_to_twokeys.f_hello = me.hello
        WHERE fourkeys_to_twokeys.pilot_sequence != ? AND ( bar = ? OR bar = ? ) AND ( foo = ? OR foo = ? ) AND ( goodbye = ? OR goodbye = ? ) AND ( hello = ? OR hello = ? ) AND sensors != ?
      )
    )
  ',
  [
    "'666'",
    ("'1'", "'2'") x 4,
    "'c'",
  ],
  'Correct update-SQL with multicolumn in support',
);

# make a *premultiplied* join stick
my $fks_premulti = $fks->search({ 'twokeys.artist' => { '!=' => 666 } });

$schema->storage->debugobj ($debugobj);
$schema->storage->debug (1);
$fks_premulti->update ({ read_count => \ 'read_count + 1' });
$schema->storage->debugobj ($orig_debugobj);
$schema->storage->debug ($orig_debug);

is_same_sql_bind (
  $sql,
  \@bind,
  'UPDATE fourkeys
   SET read_count = read_count + 1
   WHERE ( bar = ? AND foo = ? AND goodbye = ? AND hello = ? ) OR ( bar = ? AND foo = ? AND goodbye = ? AND hello = ? )',
  [ map { "'$_'" } ( (1) x 4, (2) x 4 ) ],
  'Correct update-SQL with premultiplied restricting join without pruning',
);

is ($fa->discard_changes->read_count, 13, 'Update ran only once on joined resultset');
is ($fb->discard_changes->read_count, 23, 'Update ran only once on joined resultset');
is ($fc->discard_changes->read_count, 30, 'Update did not touch outlier');


#
# Make sure multicolumn in or the equivalent functions correctly
#

my $sub_rs = $tkfks->search (
  [
    { map { $_ => 1 } qw/artist.artistid cd.cdid fourkeys.foo fourkeys.bar fourkeys.hello fourkeys.goodbye/ },
    { map { $_ => 2 } qw/artist.artistid cd.cdid fourkeys.foo fourkeys.bar fourkeys.hello fourkeys.goodbye/ },
  ],
  {
    join => [ 'fourkeys', { twokeys => [qw/artist cd/] } ],
  },
);

is ($sub_rs->count, 2, 'Only two rows from fourkeys match');

# attempts to delete a grouped rs should fail miserably
throws_ok (
  sub { $sub_rs->search ({}, { distinct => 1 })->delete },
  qr/attempted a delete operation on a resultset which does group_by/,
  'Grouped rs update/delete not allowed',
);

# grouping on PKs only should pass
$sub_rs->search (
  {},
  {
    group_by => [ reverse $sub_rs->result_source->primary_columns ],     # reverse to make sure the PK-list comparison works
  },
)->update ({ pilot_sequence => \ 'pilot_sequence + 1' });

is_deeply (
  [ $tkfks->search ({ autopilot => [qw/a b x y/]}, { order_by => 'autopilot' })
            ->get_column ('pilot_sequence')->all
  ],
  [qw/11 21 30 40/],
  'Only two rows incremented',
);

# also make sure weird scalarref usage works (RT#51409)
$tkfks->search (
  \ 'pilot_sequence BETWEEN 11 AND 21',
)->update ({ pilot_sequence => \ 'pilot_sequence + 1' });

is_deeply (
  [ $tkfks->search ({ autopilot => [qw/a b x y/]}, { order_by => 'autopilot' })
            ->get_column ('pilot_sequence')->all
  ],
  [qw/12 22 30 40/],
  'Only two rows incremented (where => scalarref works)',
);

{
  my $rs = $schema->resultset('FourKeys_to_TwoKeys')->search (
    {
      -or => [
        { 'me.pilot_sequence' => 12 },
        { 'me.autopilot'      => 'b' },
      ],
    }
  );
  lives_ok { $rs->update({ autopilot => 'z' }) }
    'Update with table name qualifier in -or conditions lives';
  is_deeply (
    [ $tkfks->search ({ pilot_sequence => [12, 22]})
              ->get_column ('autopilot')->all
    ],
    [qw/z z/],
    '... and yields the right data',
  );
}


$sub_rs->delete;
is ($tkfks->count, $tkfk_cnt -= 2, 'Only two rows deleted');

# make sure limit-only deletion works
cmp_ok ($tkfk_cnt, '>', 1, 'More than 1 row left');
$tkfks->search ({}, { rows => 1 })->delete;
is ($tkfks->count, $tkfk_cnt -= 1, 'Only one row deleted');


# check with sql-equality, as sqlite will accept most bad sql just fine
$schema->storage->debugobj ($debugobj);
$schema->storage->debug (1);

{
  my $rs = $schema->resultset('CD')->search(
    { 'me.year' => { '!=' => 2010 } },
  );

  $rs->search({}, { join => 'liner_notes' })->delete;
  is_same_sql_bind (
    $sql,
    \@bind,
    'DELETE FROM cd WHERE ( year != ? )',
    ["'2010'"],
    'Non-restricting multijoins properly thrown out'
  );

  $rs->search({}, { prefetch => 'liner_notes' })->delete;
  is_same_sql_bind (
    $sql,
    \@bind,
    'DELETE FROM cd WHERE ( year != ? )',
    ["'2010'"],
    'Non-restricting multiprefetch thrown out'
  );

  $rs->search({}, { prefetch => 'artist' })->delete;
  is_same_sql_bind (
    $sql,
    \@bind,
    'DELETE FROM cd WHERE ( cdid IN ( SELECT me.cdid FROM cd me JOIN artist artist ON artist.artistid = me.artist WHERE ( me.year != ? ) ) )',
    ["'2010'"],
    'Restricting prefetch left in, selector thrown out'
  );

  # switch artist and cd to fully qualified table names
  # make sure nothing is stripped out
  my $cd_rsrc = $schema->source('CD');
  $cd_rsrc->name('main.cd');
  $cd_rsrc->relationship_info($_)->{attrs}{cascade_delete} = 0
    for $cd_rsrc->relationships;

  my $art_rsrc = $schema->source('Artist');
  $art_rsrc->name(\'main.artist');
  $art_rsrc->relationship_info($_)->{attrs}{cascade_delete} = 0
    for $art_rsrc->relationships;

  $rs->delete;
  is_same_sql_bind (
    $sql,
    \@bind,
    'DELETE FROM main.cd WHERE ( year != ? )',
    ["'2010'"],
    'delete with fully qualified table name'
  );

  $rs->create({ title => 'foo', artist => 1, year => 2000 });
  $rs->delete_all;
  is_same_sql_bind (
    $sql,
    \@bind,
    'DELETE FROM main.cd WHERE ( cdid = ? )',
    ["'1'"],
    'delete_all with fully qualified table name'
  );

  $rs->create({ cdid => 42, title => 'foo', artist => 2, year => 2000 });
  $rs->find(42)->delete;
  is_same_sql_bind (
    $sql,
    \@bind,
    'DELETE FROM main.cd WHERE ( cdid = ? )',
    ["'42'"],
    'delete of object from table with fully qualified name'
  );

  $rs->create({ cdid => 42, title => 'foo', artist => 2, year => 2000 });
  $rs->find(42)->related_resultset('artist')->delete;
  is_same_sql_bind (
    $sql,
    \@bind,
    'DELETE FROM main.artist WHERE ( artistid IN ( SELECT me.artistid FROM main.artist me WHERE ( me.artistid = ? ) ) )',
    ["'2'"],
    'delete of related object from scalarref fully qualified named table',
  );

  $schema->resultset('Artist')->find(3)->related_resultset('cds')->delete;
  is_same_sql_bind (
    $sql,
    \@bind,
    'DELETE FROM main.cd WHERE ( artist = ? )',
    ["'3'"],
    'delete of related object from fully qualified named table',
  );

  $schema->resultset('Artist')->find(3)->cds_unordered->delete;
  is_same_sql_bind (
    $sql,
    \@bind,
    'DELETE FROM main.cd WHERE ( artist = ? )',
    ["'3'"],
    'delete of related object from fully qualified named table via relaccessor',
  );

  $rs->search({}, { prefetch => 'artist' })->delete;
  is_same_sql_bind (
    $sql,
    \@bind,
    'DELETE FROM main.cd WHERE ( cdid IN ( SELECT me.cdid FROM main.cd me JOIN main.artist artist ON artist.artistid = me.artist WHERE ( me.year != ? ) ) )',
    ["'2010'"],
    'delete with fully qualified table name and subquery correct'
  );

  # check that as_subselect_rs works ok
  # inner query is untouched, then a selector
  # and an IN condition
  $schema->resultset('CD')->search({
    'me.cdid' => 1,
    'artist.name' => 'partytimecity',
  }, {
    join => 'artist',
  })->as_subselect_rs->delete;

  is_same_sql_bind (
    $sql,
    \@bind,
    '
      DELETE FROM main.cd
      WHERE (
        cdid IN (
          SELECT me.cdid
            FROM (
              SELECT me.cdid, me.artist, me.title, me.year, me.genreid, me.single_track
                FROM main.cd me
                JOIN main.artist artist ON artist.artistid = me.artist
              WHERE artist.name = ? AND me.cdid = ?
            ) me
        )
      )
    ',
    ["'partytimecity'", "'1'"],
    'Delete from as_subselect_rs works correctly'
  );
}

$schema->storage->debugobj ($orig_debugobj);
$schema->storage->debug ($orig_debug);

done_testing;
