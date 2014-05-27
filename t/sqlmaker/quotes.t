use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;
use DBIC::DebugObj;

my $schema = DBICTest->init_schema();

$schema->connection(
  @{ $schema->storage->_dbi_connect_info },
  { AutoCommit => 1, quote_char => [qw/[ ]/] }
);

my ($sql, @bind);
$schema->storage->debugobj(DBIC::DebugObj->new(\$sql, \@bind));
$schema->storage->debug(1);

my $rs = $schema->resultset('CD')->search(
           { 'me.year' => 2001, 'artist.name' => 'Caterwauler McCrae' },
           { join => 'artist' });
my $expected_bind =   ["'Caterwauler McCrae'", "'2001'"];
eval { $rs->count };
is_same_sql_bind(
  $sql, \@bind,
  "SELECT COUNT( * ) FROM cd [me]  JOIN [artist] [artist] ON ( [artist].[artistid] = [me].[artist] ) WHERE ( [artist].[name] = ? AND [me].[year] = ? )",
  $expected_bind,
  'got correct SQL for count query with bracket quoting'
);

$schema->storage->sql_maker->quote_char('`');
$schema->storage->sql_maker->name_sep('.');

eval { $rs->count };
is_same_sql_bind(
  $sql, \@bind,
  "SELECT COUNT( * ) FROM cd `me`  JOIN `artist` `artist` ON ( `artist`.`artistid` = `me`.`artist` ) WHERE ( `artist`.`name` = ? AND `me`.`year` = ? )",
  $expected_bind,
  'got correct SQL for count query with quoting'
);

my $order = 'year DESC';
$rs = $schema->resultset('CD')->search({},
            { 'order_by' => $order });
eval { $rs->first };
like($sql, qr/ORDER BY `\Q${order}\E`/, 'quoted ORDER BY with DESC (should use a scalarref anyway)');

$rs = $schema->resultset('CD')->search({},
            { 'order_by' => \$order });
eval { $rs->first };
like($sql, qr/ORDER BY \Q${order}\E/, 'did not quote ORDER BY with scalarref');

is(
  $schema->storage->sql_maker->update('group', { name => 'Bill', order => 12 }),
  'UPDATE `group` SET `name` = ?, `order` = ?',
  'quoted table names for UPDATE' );

done_testing;
