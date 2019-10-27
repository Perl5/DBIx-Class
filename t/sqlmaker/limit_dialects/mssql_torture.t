use strict;
use warnings;
use Test::More;
use lib qw(t/lib);
use DBICTest ':DiffSQL';

my $OFFSET = DBIx::Class::SQLMaker::ClassicExtensions->__offset_bindtype;
my $TOTAL  = DBIx::Class::SQLMaker::ClassicExtensions->__total_bindtype;

my $schema = DBICTest->init_schema (
  storage_type => 'DBIx::Class::Storage::DBI::MSSQL',
  no_deploy => 1,
  quote_names => 1
);
# prime caches
$schema->storage->sql_maker;

# more involved limit dialect torture testcase migrated from the
# live mssql tests
my $tests = {
  pref_hm_and_page_and_group_rs => {

    rs => scalar $schema->resultset ('Owners')->search (
      {
        'books.id' => { '!=', undef },
        'me.name' => { '!=', 'somebogusstring' },
      },
      {
        prefetch => 'books',
        order_by => [ { -asc => \['name + ?', [ test => 'xxx' ]] }, 'me.id' ], # test bindvar propagation
        group_by => [ map { "me.$_" } $schema->source('Owners')->columns ], # the literal order_by requires an explicit group_by
        rows     => 3,
        unsafe_subselect_ok => 1,
      },
    )->page(3),

    result => {
      Top => [
        '(
          SELECT TOP 2147483647 [me].[id], [me].[name],
                                [books].[id], [books].[source], [books].[owner], [books].[title], [books].[price]
            FROM (
              SELECT TOP 2147483647 [me].[id], [me].[name]
                FROM (
                  SELECT TOP 3 [me].[id], [me].[name], [ORDER__BY__001]
                    FROM (
                      SELECT TOP 9 [me].[id], [me].[name], name + ? AS [ORDER__BY__001]
                        FROM [owners] [me]
                        LEFT JOIN [books] [books]
                          ON [books].[owner] = [me].[id]
                      WHERE [books].[id] IS NOT NULL AND [me].[name] != ?
                      GROUP BY [me].[id], [me].[name]
                      ORDER BY name + ? ASC, [me].[id]
                    ) [me]
                  ORDER BY [ORDER__BY__001] DESC, [me].[id] DESC
                ) [me]
              ORDER BY [ORDER__BY__001] ASC, [me].[id]
            ) [me]
            LEFT JOIN [books] [books]
              ON [books].[owner] = [me].[id]
          WHERE [books].[id] IS NOT NULL AND [me].[name] != ?
          ORDER BY name + ? ASC, [me].[id]
        )',
        [
          [ { dbic_colname => 'test' }
            => 'xxx' ],

          [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'me.name' }
            => 'somebogusstring' ],

          [ { dbic_colname => 'test' } => 'xxx' ],  # the extra re-order bind

          [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'me.name' }
            => 'somebogusstring' ],

          [ { dbic_colname => 'test' }
            => 'xxx' ],
        ],
      ],

      RowNumberOver => [
        '(
          SELECT TOP 2147483647 [me].[id], [me].[name],
                                [books].[id], [books].[source], [books].[owner], [books].[title], [books].[price]
            FROM (
              SELECT TOP 2147483647 [me].[id], [me].[name]
                FROM (
                  SELECT [me].[id], [me].[name],
                         ROW_NUMBER() OVER( ORDER BY [ORDER__BY__001] ASC, [me].[id] ) AS [rno__row__index]
                    FROM (
                      SELECT [me].[id], [me].[name], name + ? AS [ORDER__BY__001]
                        FROM [owners] [me]
                        LEFT JOIN [books] [books]
                          ON [books].[owner] = [me].[id]
                      WHERE [books].[id] IS NOT NULL AND [me].[name] != ?
                      GROUP BY [me].[id], [me].[name]
                    ) [me]
                ) [me]
              WHERE [rno__row__index] >= ? AND [rno__row__index] <= ?
            ) [me]
            LEFT JOIN [books] [books]
              ON [books].[owner] = [me].[id]
          WHERE [books].[id] IS NOT NULL AND [me].[name] != ?
          ORDER BY name + ? ASC, [me].[id]
        )',
        [
          [ { dbic_colname => 'test' }
            => 'xxx' ],

          [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'me.name' }
            => 'somebogusstring' ],

          [ $OFFSET => 7 ], # parameterised RNO

          [ $TOTAL => 9 ],

          [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'me.name' }
            => 'somebogusstring' ],

          [ { dbic_colname => 'test' }
            => 'xxx' ],
        ],
      ],
    }
  },

  pref_bt_and_page_and_group_rs => {

    rs => scalar $schema->resultset ('BooksInLibrary')->search (
      {
        'owner.name' => [qw/wiggle woggle/],
      },
      {
        distinct => 1,
        having => \['1 = ?', [ test => 1 ] ], #test having propagation
        prefetch => 'owner',
        rows     => 2,  # 3 results total
        order_by => [{ -desc => 'me.owner' }, 'me.id'],
        unsafe_subselect_ok => 1,
      },
    )->page(3),

    result => {
      Top => [
        '(
          SELECT TOP 2147483647 [me].[id], [me].[source], [me].[owner], [me].[title], [me].[price],
                                [owner].[id], [owner].[name]
            FROM (
              SELECT TOP 2147483647 [me].[id], [me].[source], [me].[owner], [me].[title], [me].[price]
                FROM (
                  SELECT TOP 2 [me].[id], [me].[source], [me].[owner], [me].[title], [me].[price]
                    FROM (
                      SELECT TOP 6 [me].[id], [me].[source], [me].[owner], [me].[title], [me].[price]
                        FROM [books] [me]
                        JOIN [owners] [owner]
                          ON [owner].[id] = [me].[owner]
                      WHERE ( [owner].[name] = ? OR [owner].[name] = ? ) AND [source] = ?
                      GROUP BY [me].[id], [me].[source], [me].[owner], [me].[title], [me].[price]
                      HAVING 1 = ?
                      ORDER BY [me].[owner] DESC, [me].[id]
                    ) [me]
                  ORDER BY [me].[owner] ASC, [me].[id] DESC
                ) [me]
              ORDER BY [me].[owner] DESC, [me].[id]
            ) [me]
            JOIN [owners] [owner]
              ON [owner].[id] = [me].[owner]
          WHERE ( [owner].[name] = ? OR [owner].[name] = ? ) AND [source] = ?
          ORDER BY [me].[owner] DESC, [me].[id]
        )',
        [
          # inner
          [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'owner.name' }
            => 'wiggle' ],
          [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'owner.name' }
            => 'woggle' ],
          [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' }
            => 'Library' ],
          [ { dbic_colname => 'test' }
            => '1' ],

          # outer
          [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'owner.name' }
            => 'wiggle' ],
          [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'owner.name' }
            => 'woggle' ],
          [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' }
            => 'Library' ],
        ],
      ],
      RowNumberOver => [
        '(
          SELECT TOP 2147483647 [me].[id], [me].[source], [me].[owner], [me].[title], [me].[price],
                                [owner].[id], [owner].[name]
            FROM (
              SELECT TOP 2147483647 [me].[id], [me].[source], [me].[owner], [me].[title], [me].[price]
                FROM (
                  SELECT [me].[id], [me].[source], [me].[owner], [me].[title], [me].[price],
                         ROW_NUMBER() OVER( ORDER BY [me].[owner] DESC, [me].[id] ) AS [rno__row__index]
                    FROM (
                      SELECT [me].[id], [me].[source], [me].[owner], [me].[title], [me].[price]
                        FROM [books] [me]
                        JOIN [owners] [owner]
                          ON [owner].[id] = [me].[owner]
                      WHERE ( [owner].[name] = ? OR [owner].[name] = ? ) AND [source] = ?
                      GROUP BY [me].[id], [me].[source], [me].[owner], [me].[title], [me].[price]
                      HAVING 1 = ?
                    ) [me]
                ) [me]
              WHERE [rno__row__index] >= ? AND [rno__row__index] <= ?
            ) [me]
            JOIN [owners] [owner]
              ON [owner].[id] = [me].[owner]
          WHERE ( [owner].[name] = ? OR [owner].[name] = ? ) AND [source] = ?
          ORDER BY [me].[owner] DESC, [me].[id]
        )',
        [
          # inner
          [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'owner.name' }
            => 'wiggle' ],
          [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'owner.name' }
            => 'woggle' ],
          [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' }
            => 'Library' ],
          [ { dbic_colname => 'test' }
            => '1' ],

          [ $OFFSET => 5 ],
          [ $TOTAL => 6 ],

          # outer
          [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'owner.name' }
            => 'wiggle' ],
          [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'owner.name' }
            => 'woggle' ],
          [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' }
            => 'Library' ],
        ],
      ],
    },
  },
};

for my $tname (keys %$tests) {
  for my $limtype (keys %{$tests->{$tname}{result}} ) {

    delete $schema->storage->_sql_maker->{_cached_syntax};
    $schema->storage->_sql_maker->limit_dialect ($limtype);

    is_same_sql_bind(
      $tests->{$tname}{rs}->as_query,
      @{ $tests->{$tname}{result}{$limtype} },
      "Correct SQL for $limtype on $tname",
    );
  }
}

done_testing;
