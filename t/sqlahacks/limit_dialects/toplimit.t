use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;

my $schema = DBICTest->init_schema;

# Trick the sqlite DB to use Top limit emulation
# We could test all of this via $sq->$op directly,
# but some conditions need a $rsrc
delete $schema->storage->_sql_maker->{_cached_syntax};
$schema->storage->_sql_maker->limit_dialect ('Top');

my $books_45_and_owners = $schema->resultset ('BooksInLibrary')->search ({}, { prefetch => 'owner', rows => 2, offset => 3 });

for my $null_order (
  undef,
  '',
  {},
  [],
  [{}],
) {
  my $rs = $books_45_and_owners->search ({}, {order_by => $null_order });
  is_same_sql_bind(
      $rs->as_query,
      '(SELECT TOP 2
            id, source, owner, title, price, owner__id, owner__name
          FROM (
            SELECT TOP 5
                me.id, me.source, me.owner, me.title, me.price, owner.id AS owner__id, owner.name AS owner__name
              FROM books me
              JOIN owners owner ON owner.id = me.owner
            WHERE ( source = ? )
            ORDER BY me.id
          ) me
        ORDER BY me.id DESC
       )',
    [ [ source => 'Library' ] ],
  );
}


for my $ord_set (
  {
    order_by => \'foo DESC',
    order_inner => 'foo DESC',
    order_outer => '__ORDER_BY_1 ASC',
    order_req => '__ORDER_BY_1 DESC',
    exselect_outer => '__ORDER_BY_1',
    exselect_inner => 'foo AS __ORDER_BY_1',
  },
  {
    order_by => { -asc => 'foo'  },
    order_inner => 'foo ASC',
    order_outer => '__ORDER_BY_1 DESC',
    order_req => '__ORDER_BY_1 ASC',
    exselect_outer => '__ORDER_BY_1',
    exselect_inner => 'foo AS __ORDER_BY_1',
  },
  {
    order_by => { -desc => 'foo' },
    order_inner => 'foo DESC',
    order_outer => '__ORDER_BY_1 ASC',
    order_req => '__ORDER_BY_1 DESC',
    exselect_outer => '__ORDER_BY_1',
    exselect_inner => 'foo AS __ORDER_BY_1',
  },
  {
    order_by => 'foo',
    order_inner => 'foo',
    order_outer => '__ORDER_BY_1 DESC',
    order_req => '__ORDER_BY_1',
    exselect_outer => '__ORDER_BY_1',
    exselect_inner => 'foo AS __ORDER_BY_1',
  },
  {
    order_by => [ qw{ foo me.owner}   ],
    order_inner => 'foo, me.owner',
    order_outer => '__ORDER_BY_1 DESC, me.owner DESC',
    order_req => '__ORDER_BY_1, me.owner',
    exselect_outer => '__ORDER_BY_1',
    exselect_inner => 'foo AS __ORDER_BY_1',
  },
  {
    order_by => ['foo', { -desc => 'bar' } ],
    order_inner => 'foo, bar DESC',
    order_outer => '__ORDER_BY_1 DESC, __ORDER_BY_2 ASC',
    order_req => '__ORDER_BY_1, __ORDER_BY_2 DESC',
    exselect_outer => '__ORDER_BY_1, __ORDER_BY_2',
    exselect_inner => 'foo AS __ORDER_BY_1, bar AS __ORDER_BY_2',
  },
  {
    order_by => { -asc => [qw{ foo bar }] },
    order_inner => 'foo ASC, bar ASC',
    order_outer => '__ORDER_BY_1 DESC, __ORDER_BY_2 DESC',
    order_req => '__ORDER_BY_1 ASC, __ORDER_BY_2 ASC',
    exselect_outer => '__ORDER_BY_1, __ORDER_BY_2',
    exselect_inner => 'foo AS __ORDER_BY_1, bar AS __ORDER_BY_2',
  },
  {
    order_by => [
      'foo',
      { -desc => [qw{bar}] },
      { -asc  => [qw{me.owner sensors}]},
    ],
    order_inner => 'foo, bar DESC, me.owner ASC, sensors ASC',
    order_outer => '__ORDER_BY_1 DESC, __ORDER_BY_2 ASC, me.owner DESC, __ORDER_BY_3 DESC',
    order_req => '__ORDER_BY_1, __ORDER_BY_2 DESC, me.owner ASC, __ORDER_BY_3 ASC',
    exselect_outer => '__ORDER_BY_1, __ORDER_BY_2, __ORDER_BY_3',
    exselect_inner => 'foo AS __ORDER_BY_1, bar AS __ORDER_BY_2, sensors AS __ORDER_BY_3',
  },
) {
  my $o_sel = $ord_set->{exselect_outer}
    ? ', ' . $ord_set->{exselect_outer}
    : ''
  ;
  my $i_sel = $ord_set->{exselect_inner}
    ? ', ' . $ord_set->{exselect_inner}
    : ''
  ;

  is_same_sql_bind(
    $books_45_and_owners->search ({}, {order_by => $ord_set->{order_by}})->as_query,
    "(SELECT TOP 2
          id, source, owner, title, price, owner__id, owner__name
        FROM (
          SELECT TOP 2
              id, source, owner, title, price, owner__id, owner__name$o_sel
            FROM (
              SELECT TOP 5
                  me.id, me.source, me.owner, me.title, me.price, owner.id AS owner__id, owner.name AS owner__name$i_sel
                FROM books me
                JOIN owners owner ON owner.id = me.owner
              WHERE ( source = ? )
              ORDER BY $ord_set->{order_inner}
            ) me
          ORDER BY $ord_set->{order_outer}
        ) me
      ORDER BY $ord_set->{order_req}
    )",
    [ [ source => 'Library' ] ],
  ) || die;
}

# with groupby
is_same_sql_bind (
  $books_45_and_owners->search ({}, { group_by => 'title', order_by => 'title' })->as_query,
  '(SELECT me.id, me.source, me.owner, me.title, me.price, owner.id, owner.name
      FROM (
        SELECT TOP 2 id, source, owner, title, price
          FROM (
            SELECT TOP 2
                id, source, owner, title, price, __ORDER_BY_1
              FROM (
                SELECT TOP 5
                    me.id, me.source, me.owner, me.title, me.price, title AS __ORDER_BY_1
                  FROM books me
                  JOIN owners owner ON owner.id = me.owner
                WHERE ( source = ? )
                GROUP BY title
                ORDER BY title
              ) me
            ORDER BY __ORDER_BY_1 DESC
          ) me
        ORDER BY __ORDER_BY_1
      ) me
      JOIN owners owner ON owner.id = me.owner
    WHERE ( source = ? )
    ORDER BY title
  )',
  [ [ source => 'Library' ], [ source => 'Library' ] ],
);

# test deprecated column mixing over join boundaries
my $rs_selectas_top = $schema->resultset ('BooksInLibrary')->search ({}, {
  '+select' => ['owner.name'],
  '+as' => ['owner_name'],
  join => 'owner',
  rows => 1 
});

is_same_sql_bind( $rs_selectas_top->search({})->as_query,
                  '(SELECT
                      TOP 1 me.id, me.source, me.owner, me.title, me.price,
                      owner.name AS owner_name
                    FROM books me
                    JOIN owners owner ON owner.id = me.owner
                    WHERE ( source = ? )
                    ORDER BY me.id
                   )',
                   [ [ 'source', 'Library' ] ],
                );

done_testing;
