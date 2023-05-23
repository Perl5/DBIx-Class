use strict;
use warnings;
use Test::More;

BEGIN {
  require DBIx::Class::Optional::Dependencies;
  plan skip_all => 'Test needs ' . DBIx::Class::Optional::Dependencies->req_missing_for ('id_shortener')
    unless DBIx::Class::Optional::Dependencies->req_ok_for ('id_shortener');
}

use Test::Exception;
use Data::Dumper::Concise;
use lib qw(t/lib);
use DBICTest ':DiffSQL';
use DBIx::Class::SQLMaker::Oracle;

# FIXME - TEMPORARY until this merges with master
use constant IGNORE_NONLOCAL_BINDTYPES => 1;

#
#  Offline test for connect_by
#  ( without active database connection)
#
my @handle_tests = (
    {
        connect_by  => { 'parentid' => { '-prior' => \'artistid' } },
        stmt        => '"parentid" = PRIOR artistid',
        bind        => [],
        msg         => 'Simple: "parentid" = PRIOR artistid',
    },
    {
        connect_by  => { 'parentid' => { '!=' => { '-prior' => { -ident => 'artistid' } } } },
        stmt        => '"parentid" != ( PRIOR "artistid" )',
        bind        => [],
        msg         => 'Simple: "parentid" != ( PRIOR "artistid" )',
    },
    # Examples from http://download.oracle.com/docs/cd/B19306_01/server.102/b14200/queries003.htm

    # CONNECT BY last_name != 'King' AND PRIOR employee_id = manager_id ...
    {
        connect_by  => [
            last_name => { '!=' => 'King' },
            manager_id => { '-prior' => { -ident => 'employee_id' } },
        ],
        stmt        => '( "last_name" != ? OR "manager_id" = PRIOR "employee_id" )',
        bind        => ['King'],
        msg         => 'oracle.com example #1',
    },
    # CONNECT BY PRIOR employee_id = manager_id and
    #            PRIOR account_mgr_id = customer_id ...
    {
        connect_by  => {
            manager_id => { '-prior' => { -ident => 'employee_id' } },
            customer_id => { '>', { '-prior' => \'account_mgr_id' } },
        },
        stmt        => '( "customer_id" > ( PRIOR account_mgr_id ) AND "manager_id" = PRIOR "employee_id" )',
        bind        => [],
        msg         => 'oracle.com example #2',
    },
    # CONNECT BY NOCYCLE PRIOR employee_id = manager_id AND LEVEL <= 4;
    # TODO: NOCYCLE parameter doesn't work
);

my $sqla_oracle = DBIx::Class::SQLMaker::Oracle->new( quote_char => '"', name_sep => '.' );
isa_ok($sqla_oracle, 'DBIx::Class::SQLMaker::Oracle');


for my $case (@handle_tests) {
    my ( $stmt, @bind );
    my $msg = sprintf("Offline: %s",
        $case->{msg} || substr($case->{stmt},0,25),
    );
    lives_ok(
        sub {
            ( $stmt, @bind ) = $sqla_oracle->_recurse_where( $case->{connect_by} );
            is_same_sql_bind( $stmt, \@bind, $case->{stmt}, $case->{bind},$msg )
              || diag "Search term:\n" . Dumper $case->{connect_by};
        }
    ,sprintf("lives is ok from '%s'",$msg));
}

is (
  $sqla_oracle->_shorten_identifier('short_id'),
  'short_id',
  '_shorten_identifier for short id without keywords ok'
);

is (
  $sqla_oracle->_shorten_identifier('short_id', [qw/ foo /]),
  'short_id',
  '_shorten_identifier for short id with one keyword ok'
);

is (
  $sqla_oracle->_shorten_identifier('short_id', [qw/ foo bar baz /]),
  'short_id',
  '_shorten_identifier for short id with keywords ok'
);

is (
  $sqla_oracle->_shorten_identifier('very_long_identifier_which_exceeds_the_30char_limit'),
  'VryLngIdntfrWhchExc_72M8CIDTM7',
  '_shorten_identifier without keywords ok',
);

is (
  $sqla_oracle->_shorten_identifier('very_long_identifier_which_exceeds_the_30char_limit',[qw/ foo /]),
  'Foo_72M8CIDTM7KBAUPXG48B22P4E',
  '_shorten_identifier with one keyword ok',
);
is (
  $sqla_oracle->_shorten_identifier('very_long_identifier_which_exceeds_the_30char_limit',[qw/ foo bar baz /]),
  'FooBarBaz_72M8CIDTM7KBAUPXG48B',
  '_shorten_identifier with keywords ok',
);

# test SQL generation for INSERT ... RETURNING

sub UREF { \do { my $x } };

$sqla_oracle->{bindtype} = 'columns';

for my $q ('', '"') {
  local $sqla_oracle->{quote_char} = $q;

  my ($sql, @bind) = $sqla_oracle->insert(
    'artist',
    {
      'name' => 'Testartist',
    },
    {
      'returning' => 'artistid',
      'returning_container' => [],
    },
  );

  is_same_sql_bind(
    $sql, \@bind,
    "INSERT INTO ${q}artist${q} (${q}name${q}) VALUES (?) RETURNING ${q}artistid${q} INTO ?",
    [ [ name => 'Testartist' ], [ artistid => UREF ] ],
    'sql_maker generates insert returning for one column'
  );

  ($sql, @bind) = $sqla_oracle->insert(
    'artist',
    {
      'name' => 'Testartist',
    },
    {
      'returning' => \'artistid',
      'returning_container' => [],
    },
  );

  is_same_sql_bind(
    $sql, \@bind,
    "INSERT INTO ${q}artist${q} (${q}name${q}) VALUES (?) RETURNING artistid INTO ?",
    [ [ name => 'Testartist' ], [ artistid => UREF ] ],
    'sql_maker generates insert returning for one column'
  );


  ($sql, @bind) = $sqla_oracle->insert(
    'computed_column_test',
    {
      'a_timestamp' => '2010-05-26 18:22:00',
    },
    {
      'returning' => [ 'id', 'a_computed_column', 'charfield' ],
      'returning_container' => [],
    },
  );

  is_same_sql_bind(
    $sql, \@bind,
    "INSERT INTO ${q}computed_column_test${q} (${q}a_timestamp${q}) VALUES (?) RETURNING ${q}id${q}, ${q}a_computed_column${q}, ${q}charfield${q} INTO ?, ?, ?",
    [ [ a_timestamp => '2010-05-26 18:22:00' ], [ id => UREF ], [ a_computed_column => UREF ], [ charfield => UREF ] ],
    'sql_maker generates insert returning for multiple columns'
  );


  # offline version of a couple live tests

  my $schema = DBICTest->init_schema(
    # pretend this is Oracle
    storage_type => '::DBI::Oracle::Generic',
    quote_names => $q,
  );

  # This one is testing ROWNUM, thus not directly executable on SQLite
  is_same_sql_bind(
    $schema->resultset('CD')->search(undef, {
      prefetch => 'very_long_artist_relationship',
      rows => 3,
      offset => 0,
    })->as_query,
    "(
      SELECT  ${q}me${q}.${q}cdid${q}, ${q}me${q}.${q}artist${q}, ${q}me${q}.${q}title${q}, ${q}me${q}.${q}year${q}, ${q}me${q}.${q}genreid${q}, ${q}me${q}.${q}single_track${q},
              ${q}VryLngArtstRltnshpA_5L2NK8TAMJ${q}, ${q}VryLngArtstRltnshpN_AZ6MM6EO7A${q}, ${q}VryLngArtstRltnshpR_D3D5S4YO5D${q}, ${q}VryLngArtstRltnshpC_94JLUHA0OX${q}
        FROM (
          SELECT  ${q}me${q}.${q}cdid${q}, ${q}me${q}.${q}artist${q}, ${q}me${q}.${q}title${q}, ${q}me${q}.${q}year${q}, ${q}me${q}.${q}genreid${q}, ${q}me${q}.${q}single_track${q},
                  ${q}very_long_artist_relationship${q}.${q}artistid${q} AS ${q}VryLngArtstRltnshpA_5L2NK8TAMJ${q},
                  ${q}very_long_artist_relationship${q}.${q}name${q} AS ${q}VryLngArtstRltnshpN_AZ6MM6EO7A${q},
                  ${q}very_long_artist_relationship${q}.${q}rank${q} AS ${q}VryLngArtstRltnshpR_D3D5S4YO5D${q},
                  ${q}very_long_artist_relationship${q}.${q}charfield${q} AS ${q}VryLngArtstRltnshpC_94JLUHA0OX${q}
            FROM cd ${q}me${q}
            JOIN ${q}artist${q} ${q}very_long_artist_relationship${q}
              ON ${q}very_long_artist_relationship${q}.${q}artistid${q} = ${q}me${q}.${q}artist${q}

        ) ${q}me${q}
      WHERE ROWNUM <= ?
    )",
    [
      [ $sqla_oracle->__rows_bindtype => 3 ],
    ],
    'Basic test of identifiers over the 30 char limit'
  );


  # but the rest are directly runnable
  $schema->is_executed_sql_bind(
    sub {
      my @rows = $schema->resultset('Artist')->search(
        { 'cds_very_very_very_long_relationship_name.title' => { '!=', 'EP C' } },
        {
          prefetch => 'cds_very_very_very_long_relationship_name',
          order_by => 'cds_very_very_very_long_relationship_name.title',
        }
      )->all;

      isa_ok(
        $rows[0],
        'DBICTest::Schema::Artist',
        'At least one artist from db',
      );
    },
    [[
      "SELECT  ${q}me${q}.${q}artistid${q}, ${q}me${q}.${q}name${q}, ${q}me${q}.${q}rank${q}, ${q}me${q}.${q}charfield${q},
                ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}.${q}cdid${q},
                ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}.${q}artist${q},
                ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}.${q}title${q},
                ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}.${q}year${q},
                ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}.${q}genreid${q},
                ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}.${q}single_track${q}
          FROM ${q}artist${q} ${q}me${q}
          LEFT JOIN cd ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}
            ON ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}.${q}artist${q} = ${q}me${q}.${q}artistid${q}
        WHERE ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}.${q}title${q} != ?
        ORDER BY ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}.${q}title${q}
      ",
      ( IGNORE_NONLOCAL_BINDTYPES ? 'EP C' : [{
           dbic_colname => 'cds_very_very_very_long_relationship_name.title',
           sqlt_datatype => 'varchar',
           sqlt_size => 100,
        } => 'EP C' ] ),
    ]],
    'rel name over 30 char limit with user condition, requiring walking the WHERE data structure',
  );

  my $pain_rs = $schema->resultset('Artist')->search(
    { 'me.artistid' => 1 },
    {
      join => 'cds_very_very_very_long_relationship_name',
      select => 'cds_very_very_very_long_relationship_name.title',
      as => 'title',
      group_by => 'cds_very_very_very_long_relationship_name.title',
    }
  );

  $schema->is_executed_sql_bind(
    sub {
      my $megapain_rs = $pain_rs->search(
                          {},
                          {
                            prefetch => { cds_very_very_very_long_relationship_name => 'very_long_artist_relationship' },
                            having => { 'cds_very_very_very_long_relationship_name.title' => { '!=', '' } },
                          },
                        );

      isa_ok(
        ( $megapain_rs->all )[0],
        'DBICTest::Schema::Artist',
        'At least one artist from db',
      );

      ok(
        defined( ( $megapain_rs->get_column('title')->all )[0] ),
        'get_column returns a non-null result'
      );
    },
    [
      [
        "SELECT ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}.${q}title${q},
                ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}.${q}cdid${q},
                ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}.${q}artist${q},
                ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}.${q}title${q},
                ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}.${q}year${q},
                ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}.${q}genreid${q},
                ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}.${q}single_track${q},
                ${q}very_long_artist_relationship${q}.${q}artistid${q},
                ${q}very_long_artist_relationship${q}.${q}name${q},
                ${q}very_long_artist_relationship${q}.${q}rank${q},
                ${q}very_long_artist_relationship${q}.${q}charfield${q}
          FROM ${q}artist${q} ${q}me${q}
          LEFT JOIN cd ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}
            ON ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}.${q}artist${q} = ${q}me${q}.${q}artistid${q}
          LEFT JOIN ${q}artist${q} ${q}very_long_artist_relationship${q}
            ON ${q}very_long_artist_relationship${q}.${q}artistid${q} = ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}.${q}artist${q}
        WHERE ${q}me${q}.${q}artistid${q} = ?
        GROUP BY ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}.${q}title${q}
        HAVING ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}.${q}title${q} != ?
        ",
        [{
           dbic_colname => 'me.artistid',
           sqlt_datatype => 'integer',
        } => 1 ],
        ( IGNORE_NONLOCAL_BINDTYPES ? '' : [{
           dbic_colname => 'cds_very_very_very_long_relationship_name.title',
           sqlt_datatype => 'varchar',
           sqlt_size => 100,
        } => '' ] ),
      ],
      [
        "SELECT ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}.${q}title${q}
          FROM ${q}artist${q} ${q}me${q}
          LEFT JOIN cd ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}
            ON ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}.${q}artist${q} = ${q}me${q}.${q}artistid${q}
        WHERE ${q}me${q}.${q}artistid${q} = ?
        GROUP BY ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}.${q}title${q}
        HAVING ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}.${q}title${q} != ?
        ",
        [{
           dbic_colname => 'me.artistid',
           sqlt_datatype => 'integer',
        } => 1 ],
        ( IGNORE_NONLOCAL_BINDTYPES ? '' : [{
           dbic_colname => 'cds_very_very_very_long_relationship_name.title',
           sqlt_datatype => 'varchar',
           sqlt_size => 100,
         } => '' ] ),
      ],
    ],
    'rel names over the 30 char limit using group_by/having and join'
  );


  is_same_sql_bind(
    $pain_rs->count_rs->as_query,
    "(
      SELECT COUNT( * )
        FROM (
          SELECT ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}.${q}title${q} AS ${q}CdsVryVryVryLngRltn_7TT4PIXZGX${q}
            FROM ${q}artist${q} ${q}me${q}
            LEFT JOIN cd ${q}CdsVryVryVryLngRltn_3BW932XK2E${q} ON ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}.${q}artist${q} = ${q}me${q}.${q}artistid${q}
          WHERE ${q}me${q}.${q}artistid${q} = ?
          GROUP BY ${q}CdsVryVryVryLngRltn_3BW932XK2E${q}.${q}title${q}
        ) ${q}me${q}
    )",
    [
      [{
        dbic_colname => 'me.artistid',
        sqlt_datatype => 'integer',
      } => 1 ],
    ],
    'Expected count subquery',
  );
}

done_testing;
