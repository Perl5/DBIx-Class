use strict;
use warnings;

use Test::More;
use Test::Exception;
use Data::Dumper::Concise;
use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;

my $schema = DBICTest->init_schema;

my $rs = $schema->resultset('FourKeys');

sub test_order {

  TODO: {
    my $args = shift;

    local $TODO = "Not implemented" if $args->{todo};

    lives_ok {
      is_same_sql_bind(
        $rs->search(
            { foo => 'bar' },
            {
                order_by => $args->{order_by},
                having =>
                  [ { read_count => { '>' => 5 } }, \[ 'read_count < ?', [ read_count => 8  ] ] ]
            }
          )->as_query,
        "(
          SELECT me.foo, me.bar, me.hello, me.goodbye, me.sensors, me.read_count
          FROM fourkeys me
          WHERE ( foo = ? )
          HAVING read_count > ? OR read_count < ?
          ORDER BY $args->{order_req}
        )",
        [
            [ { sqlt_datatype => 'integer', dbic_colname => 'foo' }
                => 'bar' ],
            [ { sqlt_datatype => 'int', dbic_colname => 'read_count' }
                => 5 ],
            [ { sqlt_datatype => 'int', dbic_colname => 'read_count' }
                => 8 ],
            $args->{bind}
              ? map { [ { dbic_colname => $_->[0] } => $_->[1] ] } @{ $args->{bind} }
              : ()
        ],
      ) || diag Dumper $args->{order_by};
    };
  }
}

my @tests = (
    {
        order_by  => \'foo DESC',
        order_req => 'foo DESC',
        bind      => [],
    },
    {
        order_by  => { -asc => 'foo' },
        order_req => 'foo ASC',
        bind      => [],
    },
    {
        order_by  => { -desc => \[ 'colA LIKE ?', [ colA => 'test' ] ] },
        order_req => 'colA LIKE ? DESC',
        bind      => [ [ colA => 'test' ] ],
    },
    {
        order_by  => \[ 'colA LIKE ? DESC', [ colA => 'test' ] ],
        order_req => 'colA LIKE ? DESC',
        bind      => [ [ colA => 'test' ] ],
    },
    {
        order_by => [
            { -asc  => \['colA'] },
            { -desc => \[ 'colB LIKE ?', [ colB => 'test' ] ] },
            { -asc  => \[ 'colC LIKE ?', [ colC => 'tost' ] ] },
        ],
        order_req => 'colA ASC, colB LIKE ? DESC, colC LIKE ? ASC',
        bind      => [ [ colB => 'test' ], [ colC => 'tost' ] ],
    },
    {
        todo => 1,
        order_by => [
            { -asc  => 'colA' },
            { -desc => { colB => { 'LIKE' => 'test' } } },
            { -asc  => { colC => { 'LIKE' => 'tost' } } }
        ],
        order_req => 'colA ASC, colB LIKE ? DESC, colC LIKE ? ASC',
        bind      => [ [ colB => 'test' ], [ colC => 'tost' ] ],
    },
    {
        todo => 1,
        order_by  => { -desc => { colA  => { LIKE  => 'test' } } },
        order_req => 'colA LIKE ? DESC',
        bind      => [ [ colA => 'test' ] ],
    },
);

test_order($_) for @tests;

done_testing;
