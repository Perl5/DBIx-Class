use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBICTest;
use DBICTest::Schema;
use DBIC::SqlMakerTest;
use DBIC::DebugObj;

my $schema = DBICTest::Schema->connect (DBICTest->_database, { quote_char => '`' });
# cheat
require DBIx::Class::Storage::DBI::mysql;
bless ( $schema->storage, 'DBIx::Class::Storage::DBI::mysql' );

# check that double-subqueries are properly wrapped
{
  my ($sql, @bind);
  my $debugobj = DBIC::DebugObj->new (\$sql, \@bind);
  my $orig_debugobj = $schema->storage->debugobj;
  my $orig_debug = $schema->storage->debug;

  $schema->storage->debugobj ($debugobj);
  $schema->storage->debug (1);

  # the expected SQL may seem wastefully nonsensical - this is due to
  # CD's tablename being \'cd', which triggers the "this can be anything"
  # mode, and forces a subquery. This in turn forces *another* subquery
  # because mysql is being mysql
  # Also we know it will fail - never deployed. All we care about is the
  # SQL to compare
  eval { $schema->resultset ('CD')->update({ genreid => undef }) };
  is_same_sql_bind (
    $sql,
    \@bind,
    'UPDATE cd SET `genreid` = ? WHERE `cdid` IN ( SELECT * FROM ( SELECT `me`.`cdid` FROM cd `me` ) `_forced_double_subquery` )',
    [ 'NULL' ],
    'Correct update-SQL with double-wrapped subquery',
  );

  # same comment as above
  eval { $schema->resultset ('CD')->delete };
  is_same_sql_bind (
    $sql,
    \@bind,
    'DELETE FROM cd WHERE `cdid` IN ( SELECT * FROM ( SELECT `me`.`cdid` FROM cd `me` ) `_forced_double_subquery` )',
    [],
    'Correct delete-SQL with double-wrapped subquery',
  );

  # and a couple of really contrived examples (we test them live in t/71mysql.t)
  my $rs = $schema->resultset('Artist')->search({ name => { -like => 'baby_%' } });
  my ($count_sql, @count_bind) = @${$rs->count_rs->as_query};
  eval {
    $schema->resultset('Artist')->search(
      { artistid => {
        -in => $rs->get_column('artistid')
                    ->as_query
      } },
    )->update({ name => \[ "CONCAT( `name`, '_bell_out_of_', $count_sql )", @count_bind ] });
  };

  is_same_sql_bind (
    $sql,
    \@bind,
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
    [ ("'baby_%'") x 2 ],
  );

  eval {
    $schema->resultset('CD')->search_related('artist',
      { 'artist.name' => { -like => 'baby_with_%' } }
    )->delete
  };

  is_same_sql_bind (
    $sql,
    \@bind,
    q(
      DELETE FROM `artist`
      WHERE `artistid` IN (
        SELECT *
          FROM (
            SELECT `artist`.`artistid`
              FROM cd `me`
              INNER JOIN `artist` `artist`
                ON `artist`.`artistid` = `me`.`artist`
            WHERE `artist`.`name` LIKE ?
          ) `_forced_double_subquery`
      )
    ),
    [ "'baby_with_%'" ],
  );

  $schema->storage->debugobj ($orig_debugobj);
  $schema->storage->debug ($orig_debug);
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

done_testing;
