use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBIC::SqlMakerTest;

BEGIN {
    eval "use DBD::SQLite";
    plan $@
        ? ( skip_all => 'needs DBD::SQLite for testing' )
        : ( tests => 8 );
}

use_ok('DBICTest');

my $schema = DBICTest->init_schema();

my $sql_maker = $schema->storage->sql_maker;

$sql_maker->quote_char('`');
$sql_maker->name_sep('.');

my ($sql, @bind) = $sql_maker->select(
          [
            {
              'me' => 'cd'
            },
            [
              {
                'artist' => 'artist',
                '-join_type' => ''
              },
              {
                'artist.artistid' => 'me.artist'
              }
            ]
          ],
          [
            {
              'count' => '*'
            }
          ],
          {
            'artist.name' => 'Caterwauler McCrae',
            'me.year' => 2001
          },
          [],
          undef,
          undef
);

is_same_sql_bind(
   $sql, \@bind,
   q/SELECT COUNT( * ) FROM `cd` `me`  JOIN `artist` `artist` ON ( `artist`.`artistid` = `me`.`artist` ) WHERE ( `artist`.`name` = ? AND `me`.`year` = ? )/,
   [ ['artist.name' => 'Caterwauler McCrae'], ['me.year' => 2001] ],
   'got correct SQL and bind parameters for count query with quoting'
);


($sql, @bind) = $sql_maker->select(
          [
            {
              'me' => 'cd'
            }
          ],
          [
            'me.cdid',
            'me.artist',
            'me.title',
            'me.year'
          ],
          undef,
          [
            'year DESC'
          ],
          undef,
          undef
);

TODO: {
    local $TODO = "order_by with quoting needs fixing (ash/castaway)";

    is_same_sql_bind(
        $sql, \@bind,
        q/SELECT `me`.`cdid`, `me`.`artist`, `me`.`title`, `me`.`year` FROM `cd` `me` ORDER BY `year DESC`/, [],
        'scalar ORDER BY okay (single value)'
    );
}

TODO: {
    local $TODO = "select attr with star needs fixing (mst/nate)";

    ($sql, @bind) = $sql_maker->select(
          [
            {
              'me' => 'cd'
            }
          ],
          [
            'me.*'
          ],
          undef,
          [],
          undef,
          undef
    );

    is_same_sql_bind(
      $sql, \@bind,
      q/SELECT `me`.* FROM `cd` `me`/, [],
      'select attr with me.* is right'
    );
}

($sql, @bind) = $sql_maker->select(
          [
            {
              'me' => 'cd'
            }
          ],
          [
            'me.cdid',
            'me.artist',
            'me.title',
            'me.year'
          ],
          undef,
          [
            \'year DESC'
          ],
          undef,
          undef
);

is_same_sql_bind(
  $sql, \@bind,
  q/SELECT `me`.`cdid`, `me`.`artist`, `me`.`title`, `me`.`year` FROM `cd` `me` ORDER BY year DESC/, [],
  'did not quote ORDER BY with scalarref'
);


($sql, @bind) = $sql_maker->update(
          'group',
          {
            'order' => '12',
            'name' => 'Bill'
          }
);

is_same_sql_bind(
  $sql, \@bind,
  q/UPDATE `group` SET `name` = ?, `order` = ?/, [ ['name' => 'Bill'], ['order' => '12'] ],
  'quoted table names for UPDATE'
);

$sql_maker->quote_char([qw/[ ]/]);

($sql, @bind) = $sql_maker->select(
          [
            {
              'me' => 'cd'
            },
            [
              {
                'artist' => 'artist',
                '-join_type' => ''
              },
              {
                'artist.artistid' => 'me.artist'
              }
            ]
          ],
          [
            {
              'count' => '*'
            }
          ],
          {
            'artist.name' => 'Caterwauler McCrae',
            'me.year' => 2001
          },
          [],
          undef,
          undef
);

is_same_sql_bind(
  $sql, \@bind,
  q/SELECT COUNT( * ) FROM [cd] [me]  JOIN [artist] [artist] ON ( [artist].[artistid] = [me].[artist] ) WHERE ( [artist].[name] = ? AND [me].[year] = ? )/, [ ['artist.name' => 'Caterwauler McCrae'], ['me.year' => 2001] ],
  'got correct SQL and bind parameters for count query with bracket quoting'
);


($sql, @bind) = $sql_maker->update(
          'group',
          {
            'order' => '12',
            'name' => 'Bill'
          }
);

is_same_sql_bind(
  $sql, \@bind,
  q/UPDATE [group] SET [name] = ?, [order] = ?/, [ ['name' => 'Bill'], ['order' => '12'] ],
  'bracket quoted table names for UPDATE'
);
