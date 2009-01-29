use strict;
use warnings;

use Test::More;
use IO::File;

BEGIN {
    eval "use DBD::SQLite";
    plan $@
        ? ( skip_all => 'needs DBD::SQLite for testing' )
        : ( tests => 6 );
}

use lib qw(t/lib);
use DBIC::SqlMakerTest;
use DBIC::DebugObj;

use_ok('DBICTest');
my $schema = DBICTest->init_schema();

diag('Testing against ' . join(' ', map { $schema->storage->dbh->get_info($_) } qw/17 18/));

$schema->storage->sql_maker->quote_char('`');
$schema->storage->sql_maker->name_sep('.');

my $sql;
$schema->storage->debugobj(DBIC::DebugObj->new(\$sql));
$schema->storage->debug(1);

my $rs;

$rs = $schema->resultset('CD')->search(
           { 'me.year' => 2001, 'artist.name' => 'Caterwauler McCrae' },
           { join => 'artist' });
eval { $rs->count };
ok (eq_sql
  (
    $sql,
    q/SELECT COUNT( * ) FROM `cd` `me`  JOIN `artist` `artist` ON ( `artist`.`artistid` = `me`.`artist` ) WHERE ( `artist`.`name` = ? AND `me`.`year` = ? )/,
  ),
  'got correct SQL for count query with quoting'
);


my $order = 'year DESC';
$rs = $schema->resultset('CD')->search({},
            { 'order_by' => $order });
eval { $rs->first };
ok (eq_sql
  (
    $sql,
    qq/SELECT `me`.`cdid`, `me`.`artist`, `me`.`title`, `me`.`year` FROM `cd` `me` ORDER BY `${order}`/,
  ),
  'quoted ORDER BY with DESC (should use a scalarref anyway)'
);

$rs = $schema->resultset('CD')->search({},
            { 'order_by' => \$order });
eval { $rs->first };
ok (eq_sql
  (
    $sql,
    qq/SELECT `me`.`cdid`, `me`.`artist`, `me`.`title`, `me`.`year` FROM `cd` `me` ORDER BY ${order}/,
  ),
  'did not quote ORDER BY with scalarref'
);

$schema->storage->sql_maker->quote_char([qw/[ ]/]);
$schema->storage->sql_maker->name_sep('.');

$rs = $schema->resultset('CD')->search(
           { 'me.year' => 2001, 'artist.name' => 'Caterwauler McCrae' },
           { join => 'artist' });
eval { $rs->count };
ok (eq_sql
  (
    $sql,
    qq/SELECT COUNT( * ) FROM [cd] [me]  JOIN [artist] [artist] ON ( [artist].[artistid] = [me].[artist] ) WHERE ( [artist].[name] = ? AND [me].[year] = ? )/,
  ),
  'got correct SQL for count query with bracket quoting'
);

my %data = (
       name => 'Bill',
       order => '12'
);

$schema->storage->sql_maker->quote_char('`');
$schema->storage->sql_maker->name_sep('.');

is($schema->storage->sql_maker->update('group', \%data), 'UPDATE `group` SET `name` = ?, `order` = ?', 'quoted table names for UPDATE');
