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
use DBIC::SqlMakerTest;
use DBIx::Class::SQLMaker::Oracle;

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
}

done_testing;
