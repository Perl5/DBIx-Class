use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBIC::SqlMakerTest;

BEGIN {
    eval "use DBD::SQLite";
    plan $@
        ? ( skip_all => 'needs DBD::SQLite for testing' )
        : ( tests => 12 );
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
  q/SELECT COUNT( * ) FROM `cd` `me`  JOIN `artist` `artist` ON ( `artist`.`artistid` = `me`.`artist` ) WHERE ( `artist`.`name` = ? AND `me`.`year` = ? )/, [ ['artist.name' => 'Caterwauler McCrae'], ['me.year' => 2001] ],
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
          'year DESC',
          undef,
          undef
);

is_same_sql_bind(
  $sql, \@bind,
  q/SELECT `me`.`cdid`, `me`.`artist`, `me`.`title`, `me`.`year` FROM `cd` `me` ORDER BY `year DESC`/, [],
  'scalar ORDER BY okay (single value)'
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
            'year DESC',
            'title ASC'
          ],
          undef,
          undef
);

is_same_sql_bind(
  $sql, \@bind,
  q/SELECT `me`.`cdid`, `me`.`artist`, `me`.`title`, `me`.`year` FROM `cd` `me` ORDER BY `year DESC`, `title ASC`/, [],
  'scalar ORDER BY okay (multiple values)'
);

SKIP: {
  skip "SQL::Abstract < 1.49 does not support hashrefs in order_by", 2
    if $SQL::Abstract::VERSION < 1.49;

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
            { -desc => 'year' },
            undef,
            undef
  );

  is_same_sql_bind(
    $sql, \@bind,
    q/SELECT `me`.`cdid`, `me`.`artist`, `me`.`title`, `me`.`year` FROM `cd` `me` ORDER BY `year` DESC/, [],
    'hashref ORDER BY okay (single value)'
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
              { -desc => 'year' },
              { -asc => 'title' }
            ],
            undef,
            undef
  );

  is_same_sql_bind(
    $sql, \@bind,
    q/SELECT `me`.`cdid`, `me`.`artist`, `me`.`title`, `me`.`year` FROM `cd` `me` ORDER BY `year` DESC, `title` ASC/, [],
    'hashref ORDER BY okay (multiple values)'
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
          \'year DESC',
          undef,
          undef
);

is_same_sql_bind(
  $sql, \@bind,
  q/SELECT `me`.`cdid`, `me`.`artist`, `me`.`title`, `me`.`year` FROM `cd` `me` ORDER BY year DESC/, [],
  'did not quote ORDER BY with scalarref (single value)'
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
            \'year DESC',
            \'title ASC'
          ],
          undef,
          undef
);

is_same_sql_bind(
  $sql, \@bind,
  q/SELECT `me`.`cdid`, `me`.`artist`, `me`.`title`, `me`.`year` FROM `cd` `me` ORDER BY year DESC, title ASC/, [],
  'did not quote ORDER BY with scalarref (multiple values)'
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

SKIP: {
  skip "select attr with star does not work in SQL::Abstract < 1.49", 1
    if $SQL::Abstract::VERSION < 1.49;

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
