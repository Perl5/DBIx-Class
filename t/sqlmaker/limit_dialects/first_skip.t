use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;
use DBIx::Class::SQLMaker::LimitDialects;

my ($LIMIT, $OFFSET) = (
   DBIx::Class::SQLMaker::LimitDialects->__rows_bindtype,
   DBIx::Class::SQLMaker::LimitDialects->__offset_bindtype,
);

my $schema = DBICTest->init_schema;

$schema->storage->_sql_maker->limit_dialect ('FirstSkip');

my $rs_selectas_col = $schema->resultset ('BooksInLibrary')->search ({}, {
  '+select' => ['owner.name'],
  '+as' => ['owner.name'],
  join => 'owner',
  rows => 1,
  offset => 2,
});

is_same_sql_bind(
  $rs_selectas_col->as_query,
  '(
    SELECT FIRST ? SKIP ? me.id, me.source, me.owner, me.title, me.price, owner.name
      FROM books me
      JOIN owners owner ON owner.id = me.owner
    WHERE ( source = ? )
  )',
  [
    [ $LIMIT => 1 ],
    [ $OFFSET => 2 ],
    [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' } => 'Library' ],
  ],
);

$schema->storage->_sql_maker->quote_char ([qw/ [ ] /]);
$schema->storage->_sql_maker->name_sep ('.');

my $rs_selectas_rel = $schema->resultset ('BooksInLibrary')->search ({}, {
  '+select' => ['owner.name'],
  '+as' => ['owner_name'],
  join => 'owner',
  rows => 1,
  offset => 2,
});

is_same_sql_bind(
  $rs_selectas_rel->as_query,
  '(
    SELECT FIRST ? SKIP ? [me].[id], [me].[source], [me].[owner], [me].[title], [me].[price], [owner].[name]
      FROM [books] [me]
      JOIN [owners] [owner] ON [owner].[id] = [me].[owner]
    WHERE ( [source] = ? )
  )',
  [
    [ $LIMIT => 1 ],
    [ $OFFSET => 2 ],
    [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' } => 'Library' ],
  ],
);

{
my $subq = $schema->resultset('Owners')->search({
   'count.id' => { -ident => 'owner.id' },
   'count.name' => 'fail', # no one would do this in real life, the rows makes even less sense
}, { alias => 'owner', rows => 1 })->count_rs;

my $rs_selectas_rel = $schema->resultset('BooksInLibrary')->search ({}, {
  columns => [
     { owner_name => 'owner.name' },
     { owner_books => $subq->as_query },
  ],
  join => 'owner',
  rows => 1,
  offset => 2,
});

is_same_sql_bind(
  $rs_selectas_rel->as_query,
  '(
    SELECT FIRST ? SKIP ?
        [owner].[name],
        ( SELECT COUNT(*) FROM
          ( SELECT FIRST ? [owner].[id] FROM [owners] [owner]
            WHERE [count].[id] = [owner].[id] and [count].[name] = ?
          ) [owner]
        )
      FROM [books] [me]
      JOIN [owners] [owner] ON [owner].[id] = [me].[owner]
    WHERE ( [source] = ? )
  )',
  [
    [ $LIMIT => 1 ],  # outer
    [ $OFFSET => 2 ], # outer
    [ {%$LIMIT} => 1 ],  # inner
    [ { dbic_colname => 'count.name' } => 'fail' ],
    [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' } => 'Library' ],
  ],
)
};

{
  my $rs = $schema->resultset('Artist')->search({}, {
    columns => 'name',
    offset => 1,
    order_by => 'name',
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
}, { alias => 'owner', select => ['id'], offset => 3, rows => 4 });

my $rs_selectas_rel = $schema->resultset('BooksInLibrary')->search( { -exists => $subq->as_query }, { select => ['id','owner'], rows => 1, offset => 2 } );

is_same_sql_bind(
  $rs_selectas_rel->as_query,
  '(
     SELECT FIRST ? SKIP ? [me].[id], [me].[owner]
     FROM [books] [me]
     WHERE ( ( (EXISTS (
       SELECT FIRST ? SKIP ? [owner].[id] FROM [owners] [owner] WHERE ( [books].[owner] = [owner].[id] )
     )) AND [source] = ? ) )
 )',
  [
    [ $LIMIT => 1 ],  #outer
    [ $OFFSET => 2 ], #outer
    [ {%$LIMIT} => 4 ],  #inner
    [ {%$OFFSET} => 3 ], #inner
    [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' } => 'Library' ],
  ],
  'Pagination with sub-query in WHERE works'
);

}

done_testing;
