use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBICTest ':DiffSQL';

my $schema = DBICTest->init_schema( no_deploy => 1 );

$schema->connection(
  @{ $schema->storage->_dbi_connect_info },
  { AutoCommit => 1, quote_char => [qw/[ ]/] }
);

my $rs =  $schema->resultset('CD')->search(
  { 'me.year' => 2001, 'artist.name' => 'Caterwauler McCrae' },
  { join => 'artist' }
)->count_rs;

my $expected_bind = [
  [ { dbic_colname => "artist.name", sqlt_datatype => "varchar", sqlt_size => 100 }
    => 'Caterwauler McCrae' ],
  [ { dbic_colname => "me.year", sqlt_datatype => "varchar", sqlt_size => 100 }
    => 2001 ],
];

is_same_sql_bind(
  $rs->as_query,
  "(SELECT COUNT( * ) FROM cd [me] JOIN [artist] [artist] ON [artist].[artistid] = [me].[artist] WHERE ( [artist].[name] = ? AND [me].[year] = ? ))",
  $expected_bind,
  'got correct SQL for count query with bracket quoting'
);

$schema->storage->sql_maker->quote_char('`');
$schema->storage->sql_maker->name_sep('.');

is_same_sql_bind (
  $rs->as_query,
  "(SELECT COUNT( * ) FROM cd `me`  JOIN `artist` `artist` ON ( `artist`.`artistid` = `me`.`artist` ) WHERE ( `artist`.`name` = ? AND `me`.`year` = ? ))",
  $expected_bind,
  'got correct SQL for count query with mysql quoting'
);

# !!! talk to ribasushi *explicitly* before modfying these tests !!!
{
  is_same_sql_bind(
    $schema->resultset('CD')->search({}, { order_by => 'year DESC', columns => 'cdid' })->as_query,
    '(SELECT `me`.`cdid` FROM cd `me` ORDER BY `year DESC`)',
    [],
    'quoted ORDER BY with DESC (should use a scalarref anyway)'
  );

  is_same_sql_bind(
    $schema->resultset('CD')->search({}, { order_by => \'year DESC', columns => 'cdid' })->as_query,
    '(SELECT `me`.`cdid` FROM cd `me` ORDER BY year DESC)',
    [],
    'did not quote ORDER BY with scalarref',
  );
}

is_same_sql(
  scalar $schema->storage->sql_maker->update('group', { order => 12, name => 'Bill' }),
  'UPDATE `group` SET `name` = ?, `order` = ?',
  'quoted table names for UPDATE' );

done_testing;
