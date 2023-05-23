use strict;
use warnings;

use lib qw(t/lib);
use Test::More;
use Test::Exception;

# MASSIVE FIXME - there is a hole in ::RSC / as_subselect_rs
# losing the order. Needs a rework/extract of the realiaser,
# and that's a whole another bag of dicks
BEGIN { $ENV{DBIC_SHUFFLE_UNORDERED_RESULTSETS} = 0 }

use DBICTest::Schema::CD;
BEGIN {
  # the default scalarref table name will not work well for this test
  DBICTest::Schema::CD->table('cd');
}

use DBIx::Class::_Util 'scope_guard';
use DBICTest;

my $schema = DBICTest->init_schema;

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
                  ->search ( [ { artist => 1, cd => 1 }, { artist => 2, cd => 2 } ], { order_by => 'artist' })
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

my $read_count_inc = 0;

is ($fks->count, 4, 'Joined FourKey count correct (2x2)');
$schema->is_executed_sql_bind( sub {
  $fks->update ({ read_count => \ 'read_count + 1' });
  $read_count_inc++;
}, [[
  'UPDATE fourkeys
   SET read_count = read_count + 1
   WHERE ( ( ( bar = ? OR bar = ? ) AND ( foo = ? OR foo = ? ) AND ( goodbye = ? OR goodbye = ? ) AND ( hello = ? OR hello = ? ) AND sensors != ? ) )
  ',
  (1, 2) x 4,
  'c',
]], 'Correct update-SQL with multijoin with pruning' );

is ($fa->discard_changes->read_count, 10 + $read_count_inc, 'Update ran only once on discard-join resultset');
is ($fb->discard_changes->read_count, 20 + $read_count_inc, 'Update ran only once on discard-join resultset');
is ($fc->discard_changes->read_count, 30, 'Update did not touch outlier');

# make the multi-join stick
my $fks_multi = $fks->search(
  { 'fourkeys_to_twokeys.pilot_sequence' => { '!=' => 666 } },
  { order_by => [ $fks->result_source->primary_columns ] },
);

# Versions of libsqlite before 3.14 do not support multicolumn-in
# namely   WHERE ( foo, bar ) IN ( SELECT foo, bar FROM ... )
#
# Run both variants to ensure the SQL is correct, and also observe whether
# the autodetection worked correctly for the current SQLite version
{
  my $detected_can_mci = $schema->storage->_use_multicolumn_in ? 1 : 0;

  for my $force_use_mci (0, 1) {

    my $orig_use_mci = $schema->storage->_use_multicolumn_in;
    my $sg = scope_guard {
      $schema->storage->_use_multicolumn_in($orig_use_mci);
    };
    $schema->storage->_use_multicolumn_in( $force_use_mci);

    $schema->is_executed_sql_bind( sub {
      my $executed = 0;
      eval {
        $fks_multi->update ({ read_count => \ 'read_count + 1' });
        $executed = 1;
        $read_count_inc++;
      };

      is(
        $executed,
        ( ( ! $detected_can_mci and $force_use_mci) ? 0 : 1 ),
        "Executed status as expected with multicolumn-in capability ($detected_can_mci) combined with forced-mci-use ($force_use_mci)"
      );

    }, [
      $force_use_mci
        ?(
          [
            'UPDATE fourkeys
             SET read_count = read_count + 1
             WHERE
              (foo, bar, hello, goodbye) IN (
                SELECT me.foo, me.bar, me.hello, me.goodbye
                  FROM fourkeys me
                  LEFT JOIN fourkeys_to_twokeys fourkeys_to_twokeys ON
                        fourkeys_to_twokeys.f_bar = me.bar
                    AND fourkeys_to_twokeys.f_foo = me.foo
                    AND fourkeys_to_twokeys.f_goodbye = me.goodbye
                    AND fourkeys_to_twokeys.f_hello = me.hello
                WHERE ( bar = ? OR bar = ? ) AND ( foo = ? OR foo = ? ) AND fourkeys_to_twokeys.pilot_sequence != ? AND ( goodbye = ? OR goodbye = ? ) AND ( hello = ? OR hello = ? ) AND sensors != ?
                ORDER BY foo, bar, hello, goodbye
              )
            ',
            ( 1, 2) x 2,
            666,
            ( 1, 2) x 2,
            'c',
          ]
        )
        :(
          [ 'BEGIN' ],
          [
            'SELECT me.foo, me.bar, me.hello, me.goodbye
              FROM fourkeys me
              LEFT JOIN fourkeys_to_twokeys fourkeys_to_twokeys
                ON fourkeys_to_twokeys.f_bar = me.bar AND fourkeys_to_twokeys.f_foo = me.foo AND fourkeys_to_twokeys.f_goodbye = me.goodbye AND fourkeys_to_twokeys.f_hello = me.hello
              WHERE ( bar = ? OR bar = ? ) AND ( foo = ? OR foo = ? ) AND fourkeys_to_twokeys.pilot_sequence != ? AND ( goodbye = ? OR goodbye = ? ) AND ( hello = ? OR hello = ? ) AND sensors != ?
              GROUP BY me.foo, me.bar, me.hello, me.goodbye
              ORDER BY foo, bar, hello, goodbye
            ',
            (1, 2) x 2,
            666,
            (1, 2) x 2,
            'c',
          ],
          [
            'UPDATE fourkeys
             SET read_count = read_count + 1
             WHERE ( bar = ? AND foo = ? AND goodbye = ? AND hello = ? ) OR ( bar = ? AND foo = ? AND goodbye = ? AND hello = ? )
            ',
            ( (1) x 4, (2) x 4 ),
          ],
          [ 'COMMIT' ],
        )
    ], "Correct update-SQL with multijoin without pruning ( use_multicolumn_in forced to: $force_use_mci )" );

    is ($fa->discard_changes->read_count, 10 + $read_count_inc, 'Update ran expected amount of times on joined resultset');
    is ($fb->discard_changes->read_count, 20 + $read_count_inc, 'Update ran expected amount of times on joined resultset');
    is ($fc->discard_changes->read_count, 30, 'Update did not touch outlier');

    $schema->is_executed_sql_bind( sub {
      my $executed = 0;
      eval {
        my $res = $fks_multi->search (\' "blah" = "bleh" ')->delete;
        $executed = 1;
        ok ($res, 'operation is true');
        cmp_ok ($res, '==', 0, 'zero rows affected');
      };

      is(
        $executed,
        ( ( ! $detected_can_mci and $force_use_mci) ? 0 : 1 ),
        "Executed status as expected with multicolumn-in capability ($detected_can_mci) combined with forced-mci-use ($force_use_mci)"
      );

    }, [
      $force_use_mci
        ? (
          [
            'DELETE FROM fourkeys
              WHERE ( foo, bar, hello, goodbye ) IN (
                SELECT me.foo, me.bar, me.hello, me.goodbye
                  FROM fourkeys me
                  LEFT JOIN fourkeys_to_twokeys fourkeys_to_twokeys
                    ON    fourkeys_to_twokeys.f_bar = me.bar
                      AND fourkeys_to_twokeys.f_foo = me.foo
                      AND fourkeys_to_twokeys.f_goodbye = me.goodbye
                      AND fourkeys_to_twokeys.f_hello = me.hello
                WHERE
                  "blah" = "bleh"
                    AND
                  ( bar = ? OR bar = ? )
                    AND
                  ( foo = ? OR foo = ? )
                    AND
                  fourkeys_to_twokeys.pilot_sequence != ?
                    AND
                  ( goodbye = ? OR goodbye = ? )
                    AND
                  ( hello = ? OR hello = ? )
                    AND
                  sensors != ?
                ORDER BY foo, bar, hello, goodbye
            )',
            (1, 2) x 2,
            666,
            (1, 2) x 2,
            'c',
          ]
        )
        : (
          [ 'BEGIN' ],
          [
            'SELECT me.foo, me.bar, me.hello, me.goodbye
              FROM fourkeys me
              LEFT JOIN fourkeys_to_twokeys fourkeys_to_twokeys
                ON fourkeys_to_twokeys.f_bar = me.bar AND fourkeys_to_twokeys.f_foo = me.foo AND fourkeys_to_twokeys.f_goodbye = me.goodbye AND fourkeys_to_twokeys.f_hello = me.hello
              WHERE "blah" = "bleh" AND ( bar = ? OR bar = ? ) AND ( foo = ? OR foo = ? ) AND fourkeys_to_twokeys.pilot_sequence != ? AND ( goodbye = ? OR goodbye = ? ) AND ( hello = ? OR hello = ? ) AND sensors != ?
              GROUP BY me.foo, me.bar, me.hello, me.goodbye
              ORDER BY foo, bar, hello, goodbye
            ',
            (1, 2) x 2,
            666,
            (1, 2) x 2,
            'c',
          ],
          [ 'COMMIT' ],
        )
    ], 'Correct null-delete-SQL with multijoin without pruning' );

    is ($fa->discard_changes->read_count, 10 + $read_count_inc, 'Noop update did not touch anything');
    is ($fb->discard_changes->read_count, 20 + $read_count_inc, 'Noop update did not touch anything');
    is ($fc->discard_changes->read_count, 30, 'Update did not touch outlier');


    $schema->is_executed_sql_bind( sub {
      my $executed = 0;

      eval {
        $fks->search({ 'twokeys.artist' => { '!=' => 666 } })->update({ read_count => \ 'read_count + 1' });
        $executed = 1;
        $read_count_inc++;
      };

      is(
        $executed,
        ( ( ! $detected_can_mci and $force_use_mci) ? 0 : 1 ),
        "Executed status as expected with multicolumn-in capability ($detected_can_mci) combined with forced-mci-use ($force_use_mci)"
      );
    }, [
      $force_use_mci
        ? (
          [
            'UPDATE fourkeys SET read_count = read_count + 1
              WHERE ( foo, bar, hello, goodbye ) IN (
                SELECT me.foo, me.bar, me.hello, me.goodbye
                  FROM fourkeys me
                    LEFT JOIN fourkeys_to_twokeys fourkeys_to_twokeys ON
                          fourkeys_to_twokeys.f_bar = me.bar
                      AND fourkeys_to_twokeys.f_foo = me.foo
                      AND fourkeys_to_twokeys.f_goodbye = me.goodbye
                      AND fourkeys_to_twokeys.f_hello = me.hello
                    LEFT JOIN twokeys twokeys
                      ON twokeys.artist = fourkeys_to_twokeys.t_artist AND twokeys.cd = fourkeys_to_twokeys.t_cd
                    WHERE ( bar = ? OR bar = ? ) AND ( foo = ? OR foo = ? ) AND ( goodbye = ? OR goodbye = ? ) AND ( hello = ? OR hello = ? ) AND sensors != ? AND twokeys.artist != ?
            )',
            (1, 2) x 4,
            'c',
            666,
          ]
        )
        : (
          [ 'BEGIN' ],
          [
            'SELECT me.foo, me.bar, me.hello, me.goodbye
              FROM fourkeys me
              LEFT JOIN fourkeys_to_twokeys fourkeys_to_twokeys
                ON fourkeys_to_twokeys.f_bar = me.bar AND fourkeys_to_twokeys.f_foo = me.foo AND fourkeys_to_twokeys.f_goodbye = me.goodbye AND fourkeys_to_twokeys.f_hello = me.hello
              LEFT JOIN twokeys twokeys
                ON twokeys.artist = fourkeys_to_twokeys.t_artist AND twokeys.cd = fourkeys_to_twokeys.t_cd
              WHERE ( bar = ? OR bar = ? ) AND ( foo = ? OR foo = ? ) AND ( goodbye = ? OR goodbye = ? ) AND ( hello = ? OR hello = ? ) AND sensors != ? AND twokeys.artist != ?
              GROUP BY me.foo, me.bar, me.hello, me.goodbye
            ',
            (1, 2) x 4,
            'c',
            666,
          ],
          [
            'UPDATE fourkeys
             SET read_count = read_count + 1
             WHERE ( bar = ? AND foo = ? AND goodbye = ? AND hello = ? ) OR ( bar = ? AND foo = ? AND goodbye = ? AND hello = ? )
            ',
            ( (1) x 4, (2) x 4 ),
          ],
          [ 'COMMIT' ],
        )
    ], 'Correct update-SQL with premultiplied restricting join without pruning' );

    is ($fa->discard_changes->read_count, 10 + $read_count_inc, 'Update ran expected amount of times on joined resultset');
    is ($fb->discard_changes->read_count, 20 + $read_count_inc, 'Update ran expected amount of times on joined resultset');
    is ($fc->discard_changes->read_count, 30, 'Update did not touch outlier');
  }
}

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

# ensure we do not do something dumb on MCI-not-supporting engines
{
  my $orig_use_mci = $schema->storage->_use_multicolumn_in;
  my $sg = scope_guard {
    $schema->storage->_use_multicolumn_in($orig_use_mci);
  };
  $schema->storage->_use_multicolumn_in(0);

  # attempts to delete a global-grouped rs should fail miserably
  throws_ok (
    sub { $sub_rs->search ({}, { distinct => 1 })->delete },
    qr/attempted a delete operation on a resultset which does group_by on columns other than the primary keys/,
    'Grouped rs update/delete not allowed',
  );
}

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
{
  my $rs = $schema->resultset('CD')->search(
    { 'me.year' => { '!=' => 2010 } },
  );

  $schema->is_executed_sql_bind( sub {
    $rs->search({}, { join => 'liner_notes' })->delete;
  }, [[
    'DELETE FROM cd WHERE ( year != ? )',
    2010,
  ]], 'Non-restricting multijoins properly thrown out' );

  $schema->is_executed_sql_bind( sub {
    $rs->search({}, { prefetch => 'liner_notes' })->delete;
  }, [[
    'DELETE FROM cd WHERE ( year != ? )',
    2010,
  ]], 'Non-restricting multiprefetch thrown out' );

  $schema->is_executed_sql_bind( sub {
    $rs->search({}, { prefetch => 'artist' })->delete;
  }, [[
    'DELETE FROM cd WHERE ( cdid IN ( SELECT me.cdid FROM cd me JOIN artist artist ON artist.artistid = me.artist WHERE ( me.year != ? ) ) )',
    2010,
  ]], 'Restricting prefetch left in, selector thrown out');

### switch artist and cd to fully qualified table names
### make sure nothing is stripped out
  my $cd_rsrc = $schema->source('CD');
  $cd_rsrc->name('main.cd');
  $cd_rsrc->relationship_info($_)->{attrs}{cascade_delete} = 0
    for $cd_rsrc->relationships;

  my $art_rsrc = $schema->source('Artist');
  $art_rsrc->name(\'main.artist');
  $art_rsrc->relationship_info($_)->{attrs}{cascade_delete} = 0
    for $art_rsrc->relationships;

  $schema->is_executed_sql_bind( sub {
    $rs->delete
  }, [[
    'DELETE FROM main.cd WHERE year != ?',
    2010,
  ]], 'delete with fully qualified table name' );

  $rs->create({ title => 'foo', artist => 1, year => 2000 });
  $schema->is_executed_sql_bind( sub {
    $rs->delete_all
  }, [
    [ 'BEGIN' ],
    [
      'SELECT me.cdid, me.artist, me.title, me.year, me.genreid, me.single_track FROM main.cd me WHERE me.year != ?',
      2010,
    ],
    [
      'DELETE FROM main.cd WHERE ( cdid = ? )',
      1,
    ],
    [ 'COMMIT' ],
  ], 'delete_all with fully qualified table name' );

  $rs->create({ cdid => 42, title => 'foo', artist => 2, year => 2000 });
  my $cd42 = $rs->find(42);

  $schema->is_executed_sql_bind( sub {
    $cd42->delete
  }, [[
    'DELETE FROM main.cd WHERE cdid = ?',
    42,
  ]], 'delete of object from table with fully qualified name' );

  $schema->is_executed_sql_bind( sub {
    $cd42->related_resultset('artist')->delete
  }, [[
    'DELETE FROM main.artist WHERE ( artistid IN ( SELECT me.artistid FROM main.artist me WHERE ( me.artistid = ? ) ) )',
    2,
  ]], 'delete of related object from scalarref fully qualified named table' );

  my $art3 = $schema->resultset('Artist')->find(3);

  $schema->is_executed_sql_bind( sub {
    $art3->related_resultset('cds')->delete;
  }, [[
    'DELETE FROM main.cd WHERE ( artist = ? )',
    3,
  ]], 'delete of related object from fully qualified named table' );

  $schema->is_executed_sql_bind( sub {
    $art3->cds_unordered->delete;
  }, [[
    'DELETE FROM main.cd WHERE ( artist = ? )',
    3,
  ]], 'delete of related object from fully qualified named table via relaccessor' );

  $schema->is_executed_sql_bind( sub {
    $rs->search({}, { prefetch => 'artist' })->delete;
  }, [[
    'DELETE FROM main.cd WHERE ( cdid IN ( SELECT me.cdid FROM main.cd me JOIN main.artist artist ON artist.artistid = me.artist WHERE ( me.year != ? ) ) )',
    2010,
  ]], 'delete with fully qualified table name and subquery correct' );

  # check that as_subselect_rs works ok
  # inner query is untouched, then a selector
  # and an IN condition
  $schema->is_executed_sql_bind( sub {
    $schema->resultset('CD')->search({
      'me.cdid' => 1,
      'artist.name' => 'partytimecity',
    }, {
      join => 'artist',
    })->as_subselect_rs->delete;
  }, [[
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
    'partytimecity',
    1,
  ]], 'Delete from as_subselect_rs works correctly' );
}

done_testing;
