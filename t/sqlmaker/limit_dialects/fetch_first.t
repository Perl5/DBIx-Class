use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest ':DiffSQL';

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
      '(SELECT me.id, me.source, me.owner, me.price, owner__id, owner__name
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
    order_outer => 'ORDER__BY__001 ASC',
    order_req => 'ORDER__BY__001 DESC',
    exselect_outer => 'ORDER__BY__001',
    exselect_inner => 'title AS ORDER__BY__001',
  },
  {
    order_by => { -asc => 'title'  },
    order_inner => 'title ASC',
    order_outer => 'ORDER__BY__001 DESC',
    order_req => 'ORDER__BY__001 ASC',
    exselect_outer => 'ORDER__BY__001',
    exselect_inner => 'title AS ORDER__BY__001',
  },
  {
    order_by => { -desc => 'title' },
    order_inner => 'title DESC',
    order_outer => 'ORDER__BY__001 ASC',
    order_req => 'ORDER__BY__001 DESC',
    exselect_outer => 'ORDER__BY__001',
    exselect_inner => 'title AS ORDER__BY__001',
  },
  {
    order_by => 'title',
    order_inner => 'title',
    order_outer => 'ORDER__BY__001 DESC',
    order_req => 'ORDER__BY__001',
    exselect_outer => 'ORDER__BY__001',
    exselect_inner => 'title AS ORDER__BY__001',
  },
  {
    order_by => [ qw{ title me.owner}   ],
    order_inner => 'title, me.owner',
    order_outer => 'ORDER__BY__001 DESC, me.owner DESC',
    order_req => 'ORDER__BY__001, me.owner',
    exselect_outer => 'ORDER__BY__001',
    exselect_inner => 'title AS ORDER__BY__001',
  },
  {
    order_by => ['title', { -desc => 'bar' } ],
    order_inner => 'title, bar DESC',
    order_outer => 'ORDER__BY__001 DESC, ORDER__BY__002 ASC',
    order_req => 'ORDER__BY__001, ORDER__BY__002 DESC',
    exselect_outer => 'ORDER__BY__001, ORDER__BY__002',
    exselect_inner => 'title AS ORDER__BY__001, bar AS ORDER__BY__002',
  },
  {
    order_by => { -asc => [qw{ title bar }] },
    order_inner => 'title ASC, bar ASC',
    order_outer => 'ORDER__BY__001 DESC, ORDER__BY__002 DESC',
    order_req => 'ORDER__BY__001 ASC, ORDER__BY__002 ASC',
    exselect_outer => 'ORDER__BY__001, ORDER__BY__002',
    exselect_inner => 'title AS ORDER__BY__001, bar AS ORDER__BY__002',
  },
  {
    order_by => [
      'title',
      { -desc => [qw{bar}] },
      { -asc  => [qw{me.owner sensors}]},
    ],
    order_inner => 'title, bar DESC, me.owner ASC, sensors ASC',
    order_outer => 'ORDER__BY__001 DESC, ORDER__BY__002 ASC, me.owner DESC, ORDER__BY__003 DESC',
    order_req => 'ORDER__BY__001, ORDER__BY__002 DESC, me.owner ASC, ORDER__BY__003 ASC',
    exselect_outer => 'ORDER__BY__001, ORDER__BY__002, ORDER__BY__003',
    exselect_inner => 'title AS ORDER__BY__001, bar AS ORDER__BY__002, sensors AS ORDER__BY__003',
  },

  {
    order_by => [
      'name',
    ],
    order_inner => 'name',
    order_outer => 'name DESC',
    order_req => 'name',
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

  my $rs = $books_45_and_owners->search ({}, {order_by => $ord_set->{order_by}});

  # query actually works
  ok( defined $rs->count, 'Query actually works' );

  is_same_sql_bind(
    $rs->as_query,
    "(SELECT me.id, me.source, me.owner, me.price, owner__id, owner__name
        FROM (
          SELECT me.id, me.source, me.owner, me.price, owner__id, owner__name$o_sel
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
        SELECT me.id, me.source, me.owner, me.price, me.title
          FROM (
            SELECT me.id, me.source, me.owner, me.price, me.title
              FROM (
                SELECT me.id, me.source, me.owner, me.price, me.title
                  FROM books me
                  JOIN owners owner ON owner.id = me.owner
                WHERE ( source = ? )
                GROUP BY title
                ORDER BY title
                FETCH FIRST 5 ROWS ONLY
              ) me
            ORDER BY title DESC
            FETCH FIRST 2 ROWS ONLY
          ) me
        ORDER BY title
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
                      me.id, me.source, me.owner, me.title, me.price, owner.name
                    FROM books me
                    JOIN owners owner ON owner.id = me.owner
                    WHERE ( source = ? )
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
