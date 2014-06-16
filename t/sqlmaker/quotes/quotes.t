use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;
use DBIC::DebugObj;

my $schema = DBICTest->init_schema();

$schema->storage->sql_maker->quote_char('`');
$schema->storage->sql_maker->name_sep('.');

my ($sql, @bind);
$schema->storage->debugobj(DBIC::DebugObj->new(\$sql, \@bind));
$schema->storage->debug(1);

my $rs;

$rs = $schema->resultset('CD')->search(
           { 'me.year' => 2001, 'artist.name' => 'Caterwauler McCrae' },
           { join => 'artist' });
eval { $rs->count };
is_same_sql_bind(
  $sql, \@bind,
  "SELECT COUNT( * ) FROM cd `me`  JOIN `artist` `artist` ON ( `artist`.`artistid` = `me`.`artist` ) WHERE ( `artist`.`name` = ? AND `me`.`year` = ? )", ["'Caterwauler McCrae'", "'2001'"],
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

$schema->storage->sql_maker->quote_char([qw/[ ]/]);
$schema->storage->sql_maker->name_sep('.');

$rs = $schema->resultset('CD')->search(
           { 'me.year' => 2001, 'artist.name' => 'Caterwauler McCrae' },
           { join => 'artist' });
eval { $rs->count };
is_same_sql_bind(
  $sql, \@bind,
  "SELECT COUNT( * ) FROM cd [me]  JOIN [artist] [artist] ON ( [artist].[artistid] = [me].[artist] ) WHERE ( [artist].[name] = ? AND [me].[year] = ? )", ["'Caterwauler McCrae'", "'2001'"],
  'got correct SQL for count query with bracket quoting'
);

my %data = (
       name => 'Bill',
       order => '12'
);

$schema->storage->sql_maker->quote_char('`');
$schema->storage->sql_maker->name_sep('.');

is($schema->storage->sql_maker->update('group', \%data), 'UPDATE `group` SET `name` = ?, `order` = ?', 'quoted table names for UPDATE');

done_testing;
