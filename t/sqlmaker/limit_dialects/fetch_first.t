use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;

my $schema = DBICTest->init_schema;

# based on toplimit.t
delete $schema->storage->_sql_maker->{_cached_syntax};
$schema->storage->_sql_maker->limit_dialect ('FetchFirst');

my $books_45_and_owners = $schema->resultset ('BooksInLibrary')->search ({}, {
  prefetch => 'owner', rows => 2, offset => 3,
  columns => [ grep { $_ ne 'title' } $schema->source('BooksInLibrary')->columns ],
});

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
      '(SELECT id, source, owner, price, owner__id, owner__name
          FROM (
            SELECT me.id, me.source, me.owner, me.price, owner.id AS owner__id, owner.name AS owner__name
              FROM books me
              JOIN owners owner ON owner.id = me.owner
            WHERE ( source = ? )
            ORDER BY me.id
            FETCH FIRST 5 ROWS ONLY
          ) me
        ORDER BY me.id DESC
        FETCH FIRST 2 ROWS ONLY
       )',
    [ [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' }
        => 'Library' ] ],
  );
}


for my $ord_set (
  {
    order_by => \'title DESC',
    order_inner => 'title DESC',
    order_outer => 'ORDER__BY__1 ASC',
    order_req => 'ORDER__BY__1 DESC',
    exselect_outer => 'ORDER__BY__1',
    exselect_inner => 'title AS ORDER__BY__1',
  },
  {
    order_by => { -asc => 'title'  },
    order_inner => 'title ASC',
    order_outer => 'ORDER__BY__1 DESC',
    order_req => 'ORDER__BY__1 ASC',
    exselect_outer => 'ORDER__BY__1',
    exselect_inner => 'title AS ORDER__BY__1',
  },
  {
    order_by => { -desc => 'title' },
    order_inner => 'title DESC',
    order_outer => 'ORDER__BY__1 ASC',
    order_req => 'ORDER__BY__1 DESC',
    exselect_outer => 'ORDER__BY__1',
    exselect_inner => 'title AS ORDER__BY__1',
  },
  {
    order_by => 'title',
    order_inner => 'title',
    order_outer => 'ORDER__BY__1 DESC',
    order_req => 'ORDER__BY__1',
    exselect_outer => 'ORDER__BY__1',
    exselect_inner => 'title AS ORDER__BY__1',
  },
  {
    order_by => [ qw{ title me.owner}   ],
    order_inner => 'title, me.owner',
    order_outer => 'ORDER__BY__1 DESC, me.owner DESC',
    order_req => 'ORDER__BY__1, me.owner',
    exselect_outer => 'ORDER__BY__1',
    exselect_inner => 'title AS ORDER__BY__1',
  },
  {
    order_by => ['title', { -desc => 'bar' } ],
    order_inner => 'title, bar DESC',
    order_outer => 'ORDER__BY__1 DESC, ORDER__BY__2 ASC',
    order_req => 'ORDER__BY__1, ORDER__BY__2 DESC',
    exselect_outer => 'ORDER__BY__1, ORDER__BY__2',
    exselect_inner => 'title AS ORDER__BY__1, bar AS ORDER__BY__2',
  },
  {
    order_by => { -asc => [qw{ title bar }] },
    order_inner => 'title ASC, bar ASC',
    order_outer => 'ORDER__BY__1 DESC, ORDER__BY__2 DESC',
    order_req => 'ORDER__BY__1 ASC, ORDER__BY__2 ASC',
    exselect_outer => 'ORDER__BY__1, ORDER__BY__2',
    exselect_inner => 'title AS ORDER__BY__1, bar AS ORDER__BY__2',
  },
  {
    order_by => [
      'title',
      { -desc => [qw{bar}] },
      { -asc  => [qw{me.owner sensors}]},
    ],
    order_inner => 'title, bar DESC, me.owner ASC, sensors ASC',
    order_outer => 'ORDER__BY__1 DESC, ORDER__BY__2 ASC, me.owner DESC, ORDER__BY__3 DESC',
    order_req => 'ORDER__BY__1, ORDER__BY__2 DESC, me.owner ASC, ORDER__BY__3 ASC',
    exselect_outer => 'ORDER__BY__1, ORDER__BY__2, ORDER__BY__3',
    exselect_inner => 'title AS ORDER__BY__1, bar AS ORDER__BY__2, sensors AS ORDER__BY__3',
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
    "(SELECT id, source, owner, price, owner__id, owner__name
        FROM (
          SELECT id, source, owner, price, owner__id, owner__name$o_sel
            FROM (
              SELECT me.id, me.source, me.owner, me.price, owner.id AS owner__id, owner.name AS owner__name$i_sel
                FROM books me
                JOIN owners owner ON owner.id = me.owner
              WHERE ( source = ? )
              ORDER BY $ord_set->{order_inner}
              FETCH FIRST 5 ROWS ONLY
            ) me
          ORDER BY $ord_set->{order_outer}
          FETCH FIRST 2 ROWS ONLY
        ) me
      ORDER BY $ord_set->{order_req}
      FETCH FIRST 2 ROWS ONLY
    )",
    [ [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' }
        => 'Library' ] ],
  );
}

# with groupby
is_same_sql_bind (
  $books_45_and_owners->search ({}, { group_by => 'title', order_by => 'title' })->as_query,
  '(SELECT me.id, me.source, me.owner, me.price, owner.id, owner.name
      FROM (
        SELECT id, source, owner, price, ORDER__BY__1 AS title
          FROM (
            SELECT id, source, owner, price, ORDER__BY__1
              FROM (
                SELECT me.id, me.source, me.owner, me.price, title AS ORDER__BY__1
                  FROM books me
                  JOIN owners owner ON owner.id = me.owner
                WHERE ( source = ? )
                GROUP BY title
                ORDER BY title
                FETCH FIRST 5 ROWS ONLY
              ) me
            ORDER BY ORDER__BY__1 DESC
            FETCH FIRST 2 ROWS ONLY
          ) me
        ORDER BY ORDER__BY__1
        FETCH FIRST 2 ROWS ONLY
      ) me
      JOIN owners owner ON owner.id = me.owner
    WHERE ( source = ? )
    ORDER BY title
  )',
  [ map { [
    { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' }
      => 'Library' ]
  } (1,2) ],
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
                      me.id, me.source, me.owner, me.title, me.price,
                      owner.name AS owner_name
                    FROM books me
                    JOIN owners owner ON owner.id = me.owner
                    WHERE ( source = ? )
                    ORDER BY me.id
                    FETCH FIRST 1 ROWS ONLY
                   )',
                  [ [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' }
                    => 'Library' ] ],
                );

{
  my $rs = $schema->resultset('Artist')->search({}, {
    columns => 'artistid',
    offset => 1,
    order_by => 'artistid',
  });
  local $rs->result_source->{name} = "weird \n newline/multi \t \t space containing \n table";

  like (
    ${$rs->as_query}->[0],
    qr| weird \s \n \s newline/multi \s \t \s \t \s space \s containing \s \n \s table|x,
    'Newlines/spaces preserved in final sql',
  );
}

done_testing;
