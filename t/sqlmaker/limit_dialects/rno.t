use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;
use DBIx::Class::SQLMaker::LimitDialects;

my ($TOTAL, $OFFSET) = (
   DBIx::Class::SQLMaker::LimitDialects->__total_bindtype,
   DBIx::Class::SQLMaker::LimitDialects->__offset_bindtype,
);

my $schema = DBICTest->init_schema;

$schema->storage->_sql_maker->limit_dialect ('RowNumberOver');

my $rs_selectas_col = $schema->resultset ('BooksInLibrary')->search ({}, {
  '+select' => ['owner.name'],
  '+as' => ['owner.name'],
  join => 'owner',
  rows => 1,
});

is_same_sql_bind(
  $rs_selectas_col->as_query,
  '(
    SELECT  id, source, owner, title, price,
            owner__name
      FROM (
        SELECT  id, source, owner, title, price,
                owner__name,
                ROW_NUMBER() OVER( ) AS rno__row__index
          FROM (
            SELECT  me.id, me.source, me.owner, me.title, me.price,
                    owner.name AS owner__name
              FROM books me
              JOIN owners owner ON owner.id = me.owner
            WHERE ( source = ? )
          ) me
      ) me
    WHERE rno__row__index >= ? AND rno__row__index <= ?
  )',
  [
    [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' } => 'Library' ],
    [ $OFFSET => 1 ],
    [ $TOTAL => 1 ],
  ],
);

$schema->storage->_sql_maker->quote_char ([qw/ [ ] /]);
$schema->storage->_sql_maker->name_sep ('.');

my $rs_selectas_rel = $schema->resultset ('BooksInLibrary')->search ({}, {
  '+select' => ['owner.name'],
  '+as' => ['owner_name'],
  join => 'owner',
  rows => 1,
});

is_same_sql_bind(
  $rs_selectas_rel->as_query,
  '(
    SELECT  [id], [source], [owner], [title], [price],
            [owner_name]
      FROM (
        SELECT  [id], [source], [owner], [title], [price],
                [owner_name],
                ROW_NUMBER() OVER( ) AS [rno__row__index]
          FROM (
            SELECT  [me].[id], [me].[source], [me].[owner], [me].[title], [me].[price],
                    [owner].[name] AS [owner_name]
              FROM [books] [me]
              JOIN [owners] [owner] ON [owner].[id] = [me].[owner]
            WHERE ( [source] = ? )
          ) [me]
      ) [me]
    WHERE [rno__row__index] >= ? AND [rno__row__index] <= ?
  )',
  [
    [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' } => 'Library' ],
    [ $OFFSET => 1 ],
    [ $TOTAL => 1 ],
  ],
);

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


done_testing;
