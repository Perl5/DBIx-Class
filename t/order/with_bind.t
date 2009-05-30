use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;

my $schema = DBICTest->init_schema;

my $rs = $schema->resultset('FourKeys');

sub test_order {
    my $args = shift;

    my $req_order =
      $args->{order_req}
      ? "ORDER BY $args->{order_req}"
      : '';

    is_same_sql_bind(
        $rs->search(
            { foo => 'bar' },
            {
                order_by => $args->{order_by},
                having =>
                  [ { read_count => { '>' => 5 } }, \[ 'read_count < ?', 8 ] ]
            }
          )->as_query,
        "(
          SELECT me.foo, me.bar, me.hello, me.goodbye, me.sensors, me.read_count 
          FROM fourkeys me 
          WHERE ( foo = ? ) 
          HAVING read_count > ? OR read_count < ?
          $req_order
        )",
        [
            [qw(foo bar)], [qw(read_count 5)],
            8, $args->{bind} ? @{ $args->{bind} } : ()
        ],
    );
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
        order_by  => { -desc => \[ 'colA LIKE ?', 'test' ] },
        order_req => 'colA LIKE ? DESC',
        bind      => [qw(test)],
    },
    {
        order_by  => \[ 'colA LIKE ? DESC', 'test' ],
        order_req => 'colA LIKE ? DESC',
        bind      => [qw(test)],
    },
    {
        order_by => [
            { -asc  => \['colA'] },
            { -desc => \[ 'colB LIKE ?', 'test' ] },
            { -asc  => \[ 'colC LIKE ?', 'tost' ] }
        ],
        order_req => 'colA ASC, colB LIKE ? DESC, colC LIKE ? ASC',
        bind      => [qw(test tost)],
    },
    {    # this would be really really nice!
        order_by => [
            { -asc  => 'colA' },
            { -desc => { colB => { 'LIKE' => 'test' } } },
            { -asc  => { colC => { 'LIKE' => 'tost' } } }
        ],
        order_req => 'colA ASC, colB LIKE ? DESC, colC LIKE ? ASC',
        bind      => [ [ colB => 'test' ], [ colC => 'tost' ] ],      # ???
    },
    {
        order_by  => { -desc => { colA  => { LIKE  => 'test' } } },
        order_req => 'colA LIKE ? DESC',
        bind      => [qw(test)],
    },
);

plan( tests => scalar @tests );

test_order($_) for @tests;

