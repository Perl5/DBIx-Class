use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBICTest ':DiffSQL';

my $schema = DBICTest::Schema->connect (DBICTest->_database, { quote_char => '`' });
# cheat
require DBIx::Class::Storage::DBI::mysql;
*DBIx::Class::Storage::DBI::mysql::_get_server_version = sub { 5 };
bless ( $schema->storage, 'DBIx::Class::Storage::DBI::mysql' );

# check that double-subqueries are properly wrapped
{
  # the expected SQL may seem wastefully nonsensical - this is due to
  # CD's tablename being \'cd', which triggers the "this can be anything"
  # mode, and forces a subquery. This in turn forces *another* subquery
  # because mysql is being mysql
  # Also we know it will fail - never deployed. All we care about is the
  # SQL to compare, hence the eval
  $schema->is_executed_sql_bind( sub {
    eval { $schema->resultset ('CD')->update({ genreid => undef }) }
  },[[
    'UPDATE cd SET `genreid` = ? WHERE `cdid` IN ( SELECT * FROM ( SELECT `me`.`cdid` FROM cd `me` ) `_forced_double_subquery` )',
    [ { dbic_colname => "genreid", sqlt_datatype => "integer" }  => undef ],
  ]], 'Correct update-SQL with double-wrapped subquery' );

  # same comment as above
  $schema->is_executed_sql_bind( sub {
    eval { $schema->resultset ('CD')->delete }
  }, [[
    'DELETE FROM cd WHERE `cdid` IN ( SELECT * FROM ( SELECT `me`.`cdid` FROM cd `me` ) `_forced_double_subquery` )',
  ]], 'Correct delete-SQL with double-wrapped subquery' );

  # and a couple of really contrived examples (we test them live in t/71mysql.t)
  my $rs = $schema->resultset('Artist')->search({ name => { -like => 'baby_%' } });
  my ($count_sql, @count_bind) = @${$rs->count_rs->as_query};
  $schema->is_executed_sql_bind( sub {
    eval {
      $schema->resultset('Artist')->search(
        { artistid => {
          -in => $rs->get_column('artistid')
                      ->as_query
        } },
      )->update({ name => \[ "CONCAT( `name`, '_bell_out_of_', $count_sql )", @count_bind ] });
    }
  }, [[
    q(
      UPDATE `artist`
        SET `name` = CONCAT(`name`, '_bell_out_of_', (
          SELECT *
            FROM (
              SELECT COUNT( * )
                FROM `artist` `me`
                WHERE `name` LIKE ?
            ) `_forced_double_subquery`
        ))
      WHERE
        `artistid` IN (
          SELECT *
            FROM (
              SELECT `me`.`artistid`
                FROM `artist` `me`
              WHERE `name` LIKE ?
            ) `_forced_double_subquery` )
    ),
    ( [ { dbic_colname => "name", sqlt_datatype => "varchar", sqlt_size => 100 }
        => 'baby_%' ]
    ) x 2
  ]]);

  $schema->is_executed_sql_bind( sub {
    eval {
      $schema->resultset('CD')->search_related('artist',
        { 'artist.name' => { -like => 'baby_with_%' } }
      )->delete
    }
  }, [[
    q(
      DELETE FROM `artist`
      WHERE `artistid` IN (
        SELECT *
          FROM (
            SELECT `artist`.`artistid`
              FROM cd `me`
              JOIN `artist` `artist`
                ON `artist`.`artistid` = `me`.`artist`
            WHERE `artist`.`name` LIKE ?
          ) `_forced_double_subquery`
      )
    ),
    [ { dbic_colname => "artist.name", sqlt_datatype => "varchar", sqlt_size => 100 }
        => 'baby_with_%' ],
  ]] );
}

# Test support for straight joins
{
  my $cdsrc = $schema->source('CD');
  my $artrel_info = $cdsrc->relationship_info ('artist');
  $cdsrc->add_relationship(
    'straight_artist',
    $artrel_info->{class},
    $artrel_info->{cond},
    { %{$artrel_info->{attrs}}, join_type => 'straight' },
  );
  is_same_sql_bind (
    $cdsrc->resultset->search({}, { prefetch => 'straight_artist' })->as_query,
    '(
      SELECT `me`.`cdid`, `me`.`artist`, `me`.`title`, `me`.`year`, `me`.`genreid`, `me`.`single_track`,
             `straight_artist`.`artistid`, `straight_artist`.`name`, `straight_artist`.`rank`, `straight_artist`.`charfield`
        FROM cd `me`
        STRAIGHT_JOIN `artist` `straight_artist` ON `straight_artist`.`artistid` = `me`.`artist`
    )',
    [],
    'straight joins correctly supported for mysql'
  );
}

# Test support for inner joins on mysql v3
for (
  [ 3 => 'INNER JOIN' ],
  [ 4 => 'JOIN' ],
) {
  my ($ver, $join_op) = @$_;

  # we do not care at this point if data is available, just do a reconnect cycle
  # to clear the server version cache and then get a new maker
  {
    $schema->storage->disconnect;
    $schema->storage->_sql_maker(undef);

    no warnings 'redefine';
    local *DBIx::Class::Storage::DBI::mysql::_get_server_version = sub { $ver };

    $schema->storage->ensure_connected;
    $schema->storage->sql_maker;
  }

  is_same_sql_bind (
    $schema->resultset('CD')->search ({}, { prefetch => 'artist' })->as_query,
    "(
      SELECT `me`.`cdid`, `me`.`artist`, `me`.`title`, `me`.`year`, `me`.`genreid`, `me`.`single_track`,
             `artist`.`artistid`, `artist`.`name`, `artist`.`rank`, `artist`.`charfield`
        FROM cd `me`
        $join_op `artist` `artist` ON `artist`.`artistid` = `me`.`artist`
    )",
    [],
    "default join type works for version $ver",
  );
}

# Test support for locking clauses
{
  # Test basic locking options
  is_same_sql_bind(
    $schema->resultset('Artist')->search({}, {for => 'update'})->as_query,
    '(
      SELECT `me`.`artistid`, `me`.`name`, `me`.`rank`, `me`.`charfield`
        FROM `artist` `me`
        FOR UPDATE
    )',
    [],
    'FOR UPDATE lock works correctly'
  );

  is_same_sql_bind(
    $schema->resultset('Artist')->search({}, {for => 'shared'})->as_query,
    '(
      SELECT `me`.`artistid`, `me`.`name`, `me`.`rank`, `me`.`charfield`
        FROM `artist` `me`
        LOCK IN SHARE MODE
    )',
    [],
    'LOCK IN SHARE MODE (deprecated shared) works correctly'
  );

  is_same_sql_bind(
    $schema->resultset('Artist')->search({}, {for => 'share'})->as_query,
    '(
      SELECT `me`.`artistid`, `me`.`name`, `me`.`rank`, `me`.`charfield`
        FROM `artist` `me`
        FOR SHARE
    )',
    [],
    'FOR SHARE (new share syntax) works correctly'
  );

  # Test hash-based locking configuration
  is_same_sql_bind(
    $schema->resultset('Artist')->search({}, {for => {type => 'update'}})->as_query,
    '(
      SELECT `me`.`artistid`, `me`.`name`, `me`.`rank`, `me`.`charfield`
        FROM `artist` `me`
        FOR UPDATE
    )',
    [],
    'Hash-based FOR UPDATE works correctly'
  );

  is_same_sql_bind(
    $schema->resultset('Artist')->search({}, {for => {type => 'share'}})->as_query,
    '(
      SELECT `me`.`artistid`, `me`.`name`, `me`.`rank`, `me`.`charfield`
        FROM `artist` `me`
        FOR SHARE
    )',
    [],
    'Hash-based FOR SHARE works correctly'
  );

  # Test NOWAIT modifier
  is_same_sql_bind(
    $schema->resultset('Artist')->search({}, {for => {type => 'update', modifier => 'nowait'}})->as_query,
    '(
      SELECT `me`.`artistid`, `me`.`name`, `me`.`rank`, `me`.`charfield`
        FROM `artist` `me`
        FOR UPDATE NOWAIT
    )',
    [],
    'FOR UPDATE NOWAIT works correctly'
  );

  is_same_sql_bind(
    $schema->resultset('Artist')->search({}, {for => {type => 'share', modifier => 'nowait'}})->as_query,
    '(
      SELECT `me`.`artistid`, `me`.`name`, `me`.`rank`, `me`.`charfield`
        FROM `artist` `me`
        FOR SHARE NOWAIT
    )',
    [],
    'FOR SHARE NOWAIT works correctly'
  );

  # Test SKIP LOCKED modifier
  is_same_sql_bind(
    $schema->resultset('Artist')->search({}, {for => {type => 'update', modifier => 'skip_locked'}})->as_query,
    '(
      SELECT `me`.`artistid`, `me`.`name`, `me`.`rank`, `me`.`charfield`
        FROM `artist` `me`
        FOR UPDATE SKIP LOCKED
    )',
    [],
    'FOR UPDATE SKIP LOCKED works correctly'
  );

  is_same_sql_bind(
    $schema->resultset('Artist')->search({}, {for => {type => 'share', modifier => 'skip_locked'}})->as_query,
    '(
      SELECT `me`.`artistid`, `me`.`name`, `me`.`rank`, `me`.`charfield`
        FROM `artist` `me`
        FOR SHARE SKIP LOCKED
    )',
    [],
    'FOR SHARE SKIP LOCKED works correctly'
  );

  # Test OF clause
  is_same_sql_bind(
    $schema->resultset('Artist')->search({}, {for => {type => 'update', of => 'artist'}})->as_query,
    '(
      SELECT `me`.`artistid`, `me`.`name`, `me`.`rank`, `me`.`charfield`
        FROM `artist` `me`
        FOR UPDATE OF `artist`
    )',
    [],
    'FOR UPDATE OF table works correctly'
  );

  # Test OF clause with multiple tables
  is_same_sql_bind(
    $schema->resultset('Artist')->search({}, {for => {type => 'share', of => ['artist', 'cd']}})->as_query,
    '(
      SELECT `me`.`artistid`, `me`.`name`, `me`.`rank`, `me`.`charfield`
        FROM `artist` `me`
        FOR SHARE OF `artist`, `cd`
    )',
    [],
    'FOR SHARE OF multiple tables works correctly'
  );

  # Test combination of OF clause and modifier
  is_same_sql_bind(
    $schema->resultset('Artist')->search({}, {
      for => {
        type => 'update',
        of => 'artist',
        modifier => 'nowait'
      }
    })->as_query,
    '(
      SELECT `me`.`artistid`, `me`.`name`, `me`.`rank`, `me`.`charfield`
        FROM `artist` `me`
        FOR UPDATE OF `artist` NOWAIT
    )',
    [],
    'FOR UPDATE OF table NOWAIT works correctly'
  );

  is_same_sql_bind(
    $schema->resultset('Artist')->search({}, {
      for => {
        type => 'share',
        of => ['artist', 'cd'],
        modifier => 'skip_locked'
      }
    })->as_query,
    '(
      SELECT `me`.`artistid`, `me`.`name`, `me`.`rank`, `me`.`charfield`
        FROM `artist` `me`
        FOR SHARE OF `artist`, `cd` SKIP LOCKED
    )',
    [],
    'FOR SHARE OF multiple tables SKIP LOCKED works correctly'
  );
}

done_testing;
