use strict;
use warnings;

use Test::More;
use IO::File;

use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;
use DBIC::DebugObj;

plan tests => 2;

my $schema = DBICTest->init_schema();

$schema->storage->sql_maker->quote_char('`');
$schema->storage->sql_maker->name_sep('.');

my ($sql, @bind);
$schema->storage->debugobj(DBIC::DebugObj->new(\$sql, \@bind)),
$schema->storage->debug(1);

my $rs;

# ->table(\'cd') should NOT be quoted
$rs = $schema->resultset('CDTableRef')->search(
           { 'me.year' => 2001, 'artist.name' => 'Caterwauler McCrae' },
           { join => 'artist' });
eval { $rs->count };
is_same_sql_bind(
  $sql, \@bind,
  "SELECT COUNT( * ) FROM cd `me`  JOIN `artist` `artist` ON ( `artist`.`artistid` = `me`.`artist` ) WHERE ( `artist`.`name` = ? AND `me`.`year` = ? )", ["'Caterwauler McCrae'", "'2001'"],
  'got correct SQL for count query with quoting'
);

# check that the table works
eval {
  $rs = $schema->resultset('CDTableRef');
  $rs->create({ cdid => 6, artist => 3, title => 'mtfnpy', year => 2009 });
  my $row = $rs->find(6);
  $row->update({ title => 'bleh' });
  $row->delete;
};
ok !$@, 'operations on scalarref table name work';
diag $@ if $@;
