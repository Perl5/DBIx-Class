use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;

my $schema = DBICTest->init_schema;

my ($ROWS, $OFFSET) = (
   DBIx::Class::SQLMaker::LimitDialects->__rows_bindtype,
   DBIx::Class::SQLMaker::LimitDialects->__offset_bindtype,
);

# based on toplimit.t
delete $schema->storage->_sql_maker->{_cached_syntax};
$schema->storage->_sql_maker->limit_dialect ('OffsetFetchNext');

my $books_45_and_owners = $schema->resultset ('BooksInLibrary')->search ({}, {
  prefetch => 'owner', rows => 2,
  columns => [ grep { $_ ne 'title' } $schema->source('BooksInLibrary')->columns ],
});

# no offset
is_same_sql_bind(
  $books_45_and_owners->as_query,
  '(
    SELECT me.id, me.source, me.owner, me.price, owner.id, owner.name
      FROM books me
      JOIN owners owner ON owner.id = me.owner
    WHERE ( source = ? )
    ORDER BY 1
    OFFSET ? ROWS FETCH NEXT ? ROWS ONLY
  )',
  [
    [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' }
      => 'Library' ],
    [ $OFFSET => 0 ],
    [ $ROWS => 2 ],
  ],
);

$books_45_and_owners = $books_45_and_owners->search({}, { offset => 3 });
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
      '(SELECT me.id, me.source, me.owner, me.price, owner.id, owner.name
         FROM books me
         JOIN owners owner ON owner.id = me.owner
         WHERE ( source = ? )
         ORDER BY 1
         OFFSET ? ROWS
         FETCH NEXT ? ROWS ONLY
       )',
    [
      [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' }
        => 'Library' ],
      [ $OFFSET => 3 ],
      [ $ROWS => 2 ],
    ],
  );
}

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

my $attr = {};
my $rs_selectas_rel = $schema->resultset('BooksInLibrary')->search(undef, {
  columns => 'me.id',
  offset => 3,
  rows => 4,
  '+columns' => { bar => \['? * ?', [ $attr => 11 ], [ $attr => 12 ]], baz => \[ '?', [ $attr => 13 ]] },
  order_by => [ \['? / ?', [ $attr => 1 ], [ $attr => 2 ]], \[ '?', [ $attr => 3 ]] ],
  having => \[ '?', [ $attr => 21 ] ],
});

is_same_sql_bind(
  $rs_selectas_rel->as_query,
  '(
    SELECT me.id, ? * ?, ?
      FROM books me
    WHERE ( source = ? )
    HAVING ?
    ORDER BY ? / ?, ?
    OFFSET ? ROWS
    FETCH NEXT ? ROWS ONLY
  )',
  [
    [ $attr => 11 ], [ $attr => 12 ], [ $attr => 13 ],
    [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' } => 'Library' ],
    [ $attr => 21 ],
    [ $attr => 1 ], [ $attr => 2 ], [ $attr => 3 ],
    [ $OFFSET => 3 ],
    [ $ROWS => 4 ],
  ],
  'Pagination with sub-query in ORDER BY works'
);


done_testing;
