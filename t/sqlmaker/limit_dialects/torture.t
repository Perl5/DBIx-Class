use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;

my $schema = DBICTest->init_schema;

my $attr = {};
my @where_bind = (
  [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' } => 'Study' ],
  [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'me.title' } => 'kama sutra' ],
  [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' } => 'Library' ],
);
my @select_bind = (
  [ $attr => 11 ], [ $attr => 12 ], [ $attr => 13 ],
);
my @group_bind = (
  [ $attr => 21 ],
);
my @having_bind = (
  [ $attr => 31 ],
);
my @order_bind = (
  [ $attr => 1 ], [ $attr => 2 ], [ $attr => 3 ],
);

my $tests = {
  LimitOffset => {
    ordered_limit_offset => [
      '(
        SELECT me.id, ? * ?, ?
          FROM books me
        WHERE source != ? AND me.title = ? AND source = ?
        GROUP BY avg(me.id / ?)
        HAVING ?
        ORDER BY ? / ?, ?
        LIMIT ?
        OFFSET ?
      )',
      [
        @select_bind,
        @where_bind,
        @group_bind,
        @having_bind,
        @order_bind,
        [ { sqlt_datatype => 'integer' } => 4 ],
        [ { sqlt_datatype => 'integer' } => 3 ],
      ],
    ],
  },

  LimitXY => {
    ordered_limit_offset => [
      '(
        SELECT me.id, ? * ?, ?
          FROM books me
        WHERE source != ? AND me.title = ? AND source = ?
        GROUP BY avg(me.id / ?)
        HAVING ?
        ORDER BY ? / ?, ?
        LIMIT ?, ?
      )',
      [
        @select_bind,
        @where_bind,
        @group_bind,
        @having_bind,
        @order_bind,
        [ { sqlt_datatype => 'integer' } => 3 ],
        [ { sqlt_datatype => 'integer' } => 4 ],
      ],
    ],
  },

  SkipFirst => {
    ordered_limit_offset => [
      '(
        SELECT SKIP ? FIRST ? me.id, ? * ?, ?
          FROM books me
        WHERE source != ? AND me.title = ? AND source = ?
        GROUP BY avg(me.id / ?)
        HAVING ?
        ORDER BY ? / ?, ?
      )',
      [
        [ { sqlt_datatype => 'integer' } => 3 ],
        [ { sqlt_datatype => 'integer' } => 4 ],
        @select_bind,
        @where_bind,
        @group_bind,
        @having_bind,
        @order_bind,
      ],
    ],
  },

  FirstSkip => {
    ordered_limit_offset => [
      '(
        SELECT FIRST ? SKIP ? me.id, ? * ?, ?
          FROM books me
        WHERE source != ? AND me.title = ? AND source = ?
        GROUP BY avg(me.id / ?)
        HAVING ?
        ORDER BY ? / ?, ?
      )',
      [
        [ { sqlt_datatype => 'integer' } => 4 ],
        [ { sqlt_datatype => 'integer' } => 3 ],
        @select_bind,
        @where_bind,
        @group_bind,
        @having_bind,
        @order_bind,
      ],
    ],
  },

  RowNumberOver => do {
    my $unordered_sql = '(
      SELECT me.id, bar, baz
        FROM (
          SELECT me.id, bar, baz, ROW_NUMBER() OVER() AS rno__row__index
            FROM (
              SELECT me.id, ? * ? AS bar, ? AS baz
                FROM books me
              WHERE source != ? AND me.title = ? AND source = ?
              GROUP BY avg(me.id / ?)
              HAVING ?
            ) me
      ) me
      WHERE rno__row__index >= ? AND rno__row__index <= ?
    )';

    my $ordered_sql = '(
      SELECT me.id, bar, baz
        FROM (
          SELECT me.id, bar, baz, ROW_NUMBER() OVER( ORDER BY ORDER__BY__1, ORDER__BY__2 ) AS rno__row__index
            FROM (
              SELECT me.id, ? * ? AS bar, ? AS baz,
                     ? / ? AS ORDER__BY__1, ? AS ORDER__BY__2
                FROM books me
              WHERE source != ? AND me.title = ? AND source = ?
              GROUP BY avg(me.id / ?)
              HAVING ?
            ) me
      ) me
      WHERE rno__row__index >= ? AND rno__row__index <= ?
    )';

    {
      limit => [$unordered_sql,
        [
          @select_bind,
          @where_bind,
          @group_bind,
          @having_bind,
          [ { sqlt_datatype => 'integer' } => 1 ],
          [ { sqlt_datatype => 'integer' } => 4 ],
        ],
      ],
      limit_offset => [$unordered_sql,
        [
          @select_bind,
          @where_bind,
          @group_bind,
          @having_bind,
          [ { sqlt_datatype => 'integer' } => 4 ],
          [ { sqlt_datatype => 'integer' } => 7 ],
        ],
      ],
      ordered_limit => [$ordered_sql,
        [
          @select_bind,
          @order_bind,
          @where_bind,
          @group_bind,
          @having_bind,
          [ { sqlt_datatype => 'integer' } => 1 ],
          [ { sqlt_datatype => 'integer' } => 4 ],
        ],
      ],
      ordered_limit_offset => [$ordered_sql,
        [
          @select_bind,
          @order_bind,
          @where_bind,
          @group_bind,
          @having_bind,
          [ { sqlt_datatype => 'integer' } => 4 ],
          [ { sqlt_datatype => 'integer' } => 7 ],
        ],
      ],
    };
  },

  RowNum => do {
    my $limit_sql = sub {
      sprintf '(
        SELECT me.id, bar, baz
          FROM (
            SELECT me.id, ? * ? AS bar, ? AS baz
              FROM books me
            WHERE source != ? AND me.title = ? AND source = ?
            GROUP BY avg(me.id / ?)
            HAVING ?
            %s
          ) me
        WHERE ROWNUM <= ?
      )', $_[0] || '';
    };

    {
      limit => [ $limit_sql->(),
        [
          @select_bind,
          @where_bind,
          @group_bind,
          @having_bind,
          [ { sqlt_datatype => 'integer' } => 4 ],
        ],
      ],
      limit_offset => [
        '(
          SELECT me.id, bar, baz
            FROM (
              SELECT me.id, bar, baz, ROWNUM rownum__index
                FROM (
                  SELECT me.id, ? * ? AS bar, ? AS baz
                    FROM books me
                  WHERE source != ? AND me.title = ? AND source = ?
                  GROUP BY avg(me.id / ?)
                  HAVING ?
                ) me
            ) me
          WHERE rownum__index BETWEEN ? AND ?
        )',
        [
          @select_bind,
          @where_bind,
          @group_bind,
          @having_bind,
          [ { sqlt_datatype => 'integer' } => 4 ],
          [ { sqlt_datatype => 'integer' } => 7 ],
        ],
      ],
      ordered_limit => [ $limit_sql->('ORDER BY ? / ?, ?'),
        [
          @select_bind,
          @where_bind,
          @group_bind,
          @having_bind,
          @order_bind,
          [ { sqlt_datatype => 'integer' } => 4 ],
        ],
      ],
      ordered_limit_offset => [
        '(
          SELECT me.id, bar, baz
            FROM (
              SELECT me.id, bar, baz, ROWNUM rownum__index
                FROM (
                  SELECT me.id, ? * ? AS bar, ? AS baz
                    FROM books me
                  WHERE source != ? AND me.title = ? AND source = ?
                  GROUP BY avg(me.id / ?)
                  HAVING ?
                  ORDER BY ? / ?, ?
                ) me
              WHERE ROWNUM <= ?
            ) me
          WHERE rownum__index >= ?
        )',
        [
          @select_bind,
          @where_bind,
          @group_bind,
          @having_bind,
          @order_bind,
          [ { sqlt_datatype => 'integer' } => 7 ],
          [ { sqlt_datatype => 'integer' } => 4 ],
        ],
      ],
    };
  },


  FetchFirst => {
    limit => [
      '(
        SELECT me.id, ? * ?, ?
          FROM books me
        WHERE source != ? AND me.title = ? AND source = ?
        GROUP BY avg(me.id / ?)
        HAVING ?
        FETCH FIRST 4 ROWS ONLY
      )',
      [
        @select_bind,
        @where_bind,
        @group_bind,
        @having_bind,
      ],
    ],
    limit_offset => [
      '(
        SELECT me.id, bar, baz
          FROM (
            SELECT me.id, ? * ? AS bar, ? AS baz
              FROM books me
            WHERE source != ? AND me.title = ? AND source = ?
            GROUP BY avg(me.id / ?)
            HAVING ?
            ORDER BY me.id
            FETCH FIRST 7 ROWS ONLY
          ) me
        ORDER BY me.id DESC
        FETCH FIRST 4 ROWS ONLY
      )',
      [
        @select_bind,
        @where_bind,
        @group_bind,
        @having_bind,
      ],
    ],
    ordered_limit => [
      '(
        SELECT me.id, ? * ?, ?
          FROM books me
        WHERE source != ? AND me.title = ? AND source = ?
        GROUP BY avg(me.id / ?)
        HAVING ?
        ORDER BY ? / ?, ?
        FETCH FIRST 4 ROWS ONLY
      )',
      [
        @select_bind,
        @where_bind,
        @group_bind,
        @having_bind,
        @order_bind,
      ],
    ],
    ordered_limit_offset => [
      '(
        SELECT me.id, bar, baz
          FROM (
            SELECT me.id, bar, baz, ORDER__BY__1, ORDER__BY__2
              FROM (
                SELECT me.id, ? * ? AS bar, ? AS baz, ? / ? AS ORDER__BY__1, ? AS ORDER__BY__2
                  FROM books me
                WHERE source != ? AND me.title = ? AND source = ?
                GROUP BY avg(me.id / ?)
                HAVING ?
                ORDER BY ? / ?, ?
                FETCH FIRST 7 ROWS ONLY
              ) me
            ORDER BY ORDER__BY__1 DESC, ORDER__BY__2 DESC
            FETCH FIRST 4 ROWS ONLY
          ) me
        ORDER BY ORDER__BY__1, ORDER__BY__2
      )',
      [
        @select_bind,
        @order_bind,
        @where_bind,
        @group_bind,
        @having_bind,
        (map { [ @$_ ] } @order_bind),  # without this is_deeply throws a fit
      ],
    ],
  },

  Top => {
    limit => [
      '(
        SELECT TOP 4 me.id, ? * ?, ?
          FROM books me
        WHERE source != ? AND me.title = ? AND source = ?
        GROUP BY avg(me.id / ?)
        HAVING ?
      )',
      [
        @select_bind,
        @where_bind,
        @group_bind,
        @having_bind,
      ],
    ],
    limit_offset => [
      '(
        SELECT TOP 4 me.id, bar, baz
          FROM (
            SELECT TOP 7 me.id, ? * ? AS bar, ? AS baz
              FROM books me
            WHERE source != ? AND me.title = ? AND source = ?
            GROUP BY avg(me.id / ?)
            HAVING ?
            ORDER BY me.id
          ) me
        ORDER BY me.id DESC
      )',
      [
        @select_bind,
        @where_bind,
        @group_bind,
        @having_bind,
      ],
    ],
    ordered_limit => [
      '(
        SELECT TOP 4 me.id, ? * ?, ?
          FROM books me
        WHERE source != ? AND me.title = ? AND source = ?
        GROUP BY avg(me.id / ?)
        HAVING ?
        ORDER BY ? / ?, ?
      )',
      [
        @select_bind,
        @where_bind,
        @group_bind,
        @having_bind,
        @order_bind,
      ],
    ],
    ordered_limit_offset => [
      '(
        SELECT me.id, bar, baz
          FROM (
            SELECT TOP 4 me.id, bar, baz, ORDER__BY__1, ORDER__BY__2
              FROM (
                SELECT TOP 7 me.id, ? * ? AS bar, ? AS baz, ? / ? AS ORDER__BY__1, ? AS ORDER__BY__2
                  FROM books me
                WHERE source != ? AND me.title = ? AND source = ?
                GROUP BY avg(me.id / ?)
                HAVING ?
                ORDER BY ? / ?, ?
              ) me
            ORDER BY ORDER__BY__1 DESC, ORDER__BY__2 DESC
          ) me
        ORDER BY ORDER__BY__1, ORDER__BY__2
      )',
      [
        @select_bind,
        @order_bind,
        @where_bind,
        @group_bind,
        @having_bind,
        (map { [ @$_ ] } @order_bind),  # without this is_deeply throws a fit
      ],
    ],
  },

  RowCountOrGenericSubQ => {
    limit => [
      '(
        SET ROWCOUNT 4
        SELECT me.id, ? * ?, ?
          FROM books me
        WHERE source != ? AND me.title = ? AND source = ?
        GROUP BY avg(me.id / ?)
        HAVING ?
        ORDER BY me.id
        SET ROWCOUNT 0
      )',
      [
        @select_bind,
        @where_bind,
        @group_bind,
        @having_bind,
      ],
    ],
    limit_offset => [
      '(
        SELECT me.id, bar, baz
          FROM (
            SELECT me.id, ? * ? AS bar, ? AS baz
              FROM books me
            WHERE source != ? AND me.title = ? AND source = ?
            GROUP BY avg( me.id / ? )
            HAVING ?
          ) me
        WHERE (
          SELECT COUNT( * )
            FROM books rownum__emulation
          WHERE rownum__emulation.id < me.id
        ) BETWEEN ? AND ?
        ORDER BY me.id
      )',
      [
        @select_bind,
        @where_bind,
        @group_bind,
        @having_bind,
        [ { sqlt_datatype => 'integer' } => 3 ],
        [ { sqlt_datatype => 'integer' } => 6 ],
      ],
    ],
  },

  GenericSubQ => {
    limit => [
      '(
        SELECT me.id, bar, baz
          FROM (
            SELECT me.id, ? * ? AS bar, ? AS baz
              FROM books me
            WHERE source != ? AND me.title = ? AND source = ?
            GROUP BY avg( me.id / ? )
            HAVING ?
          ) me
        WHERE (
          SELECT COUNT( * )
            FROM books rownum__emulation
          WHERE rownum__emulation.id < me.id
        ) < ?
        ORDER BY me.id
      )',
      [
        @select_bind,
        @where_bind,
        @group_bind,
        @having_bind,
        [ { sqlt_datatype => 'integer' } => 4 ],
      ],
    ],
    limit_offset => [
      '(
        SELECT me.id, bar, baz
          FROM (
            SELECT me.id, ? * ? AS bar, ? AS baz
              FROM books me
            WHERE source != ? AND me.title = ? AND source = ?
            GROUP BY avg( me.id / ? )
            HAVING ?
          ) me
        WHERE (
          SELECT COUNT( * )
            FROM books rownum__emulation
          WHERE rownum__emulation.id < me.id
        ) BETWEEN ? AND ?
        ORDER BY me.id
      )',
      [
        @select_bind,
        @where_bind,
        @group_bind,
        @having_bind,
        [ { sqlt_datatype => 'integer' } => 3 ],
        [ { sqlt_datatype => 'integer' } => 6 ],
      ],
    ],
  }
};

for my $limtype (sort keys %$tests) {

  delete $schema->storage->_sql_maker->{_cached_syntax};
  $schema->storage->_sql_maker->limit_dialect ($limtype);

  # chained search is necessary to exercise the recursive {where} parser
  my $rs = $schema->resultset('BooksInLibrary')->search({ 'me.title' => { '=' => 'kama sutra' } })->search({ source => { '!=', 'Study' } }, {
    columns => { identifier => 'me.id' }, # people actually do that. BLEH!!! :)
    rows => 4,
    '+columns' => { bar => \['? * ?', [ $attr => 11 ], [ $attr => 12 ]], baz => \[ '?', [ $attr => 13 ]] },
    group_by => \[ 'avg(me.id / ?)', [ $attr => 21 ] ],
    having => \[ '?', [ $attr => 31 ] ],
    ($limtype =~ /GenericSubQ/ ? ( order_by => 'me.id' ) : () ),  # needs a simple-column stable order to be happy
  });

  #
  # not all tests run on all dialects (somewhere impossible, somewhere makes no sense)
  #

  # only limit, no offset, no order
  is_same_sql_bind(
    $rs->as_query,
    @{$tests->{$limtype}{limit}},
    "$limtype: Unordered limit with select/group/having",
  ) if $tests->{$limtype}{limit};

  # limit + offset, no order
  is_same_sql_bind(
    $rs->search({}, { offset => 3 })->as_query,
    @{$tests->{$limtype}{limit_offset}},
    "$limtype: Unordered limit+offset with select/group/having",
  ) if $tests->{$limtype}{limit_offset};

  # order + limit, no offset
  $rs = $rs->search(undef, {
    order_by => [ \['? / ?', [ $attr => 1 ], [ $attr => 2 ]], \[ '?', [ $attr => 3 ]] ],
  });

  is_same_sql_bind(
    $rs->as_query,
    @{$tests->{$limtype}{ordered_limit}},
    "$limtype: Ordered limit with select/group/having",
  ) if $tests->{$limtype}{ordered_limit};

  # order + limit + offset
  is_same_sql_bind(
    $rs->search({}, { offset => 3 })->as_query,
    @{$tests->{$limtype}{ordered_limit_offset}},
    "$limtype: Ordered limit+offset with select/group/having",
  ) if $tests->{$limtype}{ordered_limit_offset};
}

done_testing;
