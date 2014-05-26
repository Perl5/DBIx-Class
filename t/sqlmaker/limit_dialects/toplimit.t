use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest ':DiffSQL';

my $schema = DBICTest->init_schema;

# Trick the sqlite DB to use Top limit emulation
# We could test all of this via $sq->$op directly,
# but some conditions need a $rsrc
delete $schema->storage->_sql_maker->{_cached_syntax};
$schema->storage->_sql_maker->limit_dialect ('Top');

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
      '(SELECT TOP 2
            me.id, me.source, me.owner, me.price, owner__id, owner__name
          FROM (
            SELECT TOP 5
                me.id, me.source, me.owner, me.price, owner.id AS owner__id, owner.name AS owner__name
              FROM books me
              JOIN owners owner ON owner.id = me.owner
            WHERE ( source = ? )
            ORDER BY me.id
          ) me
        ORDER BY me.id DESC
       )',
    [ [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' }
        => 'Library' ] ],
  );
}

{
my $subq = $schema->resultset('Owners')->search({
   'count.id' => { -ident => 'owner.id' },
}, { alias => 'owner' })->count_rs;

my $rs_selectas_rel = $schema->resultset('BooksInLibrary')->search ({}, {
  columns => [
     { owner_name => 'owner.name' },
     { owner_books => $subq->as_query },
  ],
  join => 'owner',
  rows => 2,
  offset => 3,
});

is_same_sql_bind(
  $rs_selectas_rel->as_query,
  '(
    SELECT TOP 2 owner_name, owner_books
      FROM (
            SELECT TOP 5 owner.name AS owner_name,
            ( SELECT COUNT( * )
                FROM owners owner
               WHERE ( count.id = owner.id )
            ) AS owner_books
              FROM books me
              JOIN owners owner ON owner.id = me.owner
             WHERE ( source = ? )
          ORDER BY me.id
      ) me
  ORDER BY me.id DESC
 )',
  [ [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' }
    => 'Library' ] ],
  'pagination with subqueries works'
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
    "(SELECT me.id, me.source, me.owner, me.price, owner__id, owner__name
        FROM (
          SELECT TOP 2
              me.id, me.source, me.owner, me.price, owner__id, owner__name$o_sel
            FROM (
              SELECT TOP 5
                  me.id, me.source, me.owner, me.price, owner.id AS owner__id, owner.name AS owner__name$i_sel
                FROM books me
                JOIN owners owner ON owner.id = me.owner
              WHERE ( source = ? )
              ORDER BY $ord_set->{order_inner}
            ) me
          ORDER BY $ord_set->{order_outer}
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
            SELECT TOP 2
                me.id, me.source, me.owner, me.price, me.title
              FROM (
                SELECT TOP 5
                    me.id, me.source, me.owner, me.price, me.title
                  FROM books me
                  JOIN owners owner ON owner.id = me.owner
                WHERE ( source = ? )
                GROUP BY title
                ORDER BY title
              ) me
            ORDER BY title DESC
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
                      TOP 1 me.id, me.source, me.owner, me.title, me.price,
                      owner.name
                    FROM books me
                    JOIN owners owner ON owner.id = me.owner
                    WHERE ( source = ? )
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

{
my $subq = $schema->resultset('Owners')->search({
   'books.owner' => { -ident => 'owner.id' },
}, { alias => 'owner', select => ['id'] } )->count_rs;

my $rs_selectas_rel = $schema->resultset('BooksInLibrary')->search( { -exists => $subq->as_query }, { select => ['id','owner'], rows => 1 } );

is_same_sql_bind(
  $rs_selectas_rel->as_query,
  '(SELECT TOP 1 me.id, me.owner  FROM books me WHERE ( ( (EXISTS (SELECT COUNT( * ) FROM owners owner WHERE ( books.owner = owner.id ))) AND source = ? ) ) )',
  [
    [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' } => 'Library' ],
  ],
  'Pagination with sub-query in WHERE works'
);

}

done_testing;
