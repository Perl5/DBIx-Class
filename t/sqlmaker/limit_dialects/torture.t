use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;

my $schema = DBICTest->init_schema;
my $native_limit_dialect = $schema->storage->sql_maker->{limit_dialect};

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
        SELECT me.id, owner.id, owner.name, ? * ?, ?
          FROM books me
          JOIN owners owner
            ON owner.id = me.owner
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
    limit_offset_prefetch => [
      '(
        SELECT me.name, books.id, books.source, books.owner, books.title, books.price
          FROM (
            SELECT me.name, me.id
              FROM owners me
            LIMIT ? OFFSET ?
          ) me
          LEFT JOIN books books
            ON books.owner = me.id
        ORDER BY books.owner
      )',
      [
        [ { sqlt_datatype => 'integer' } => 3 ],
        [ { sqlt_datatype => 'integer' } => 1 ],
      ]
    ],
  },

  LimitXY => {
    ordered_limit_offset => [
      '(
        SELECT me.id, owner.id, owner.name, ? * ?, ?
          FROM books me
          JOIN owners owner
            ON owner.id = me.owner
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
    limit_offset_prefetch => [
      '(
        SELECT me.name, books.id, books.source, books.owner, books.title, books.price
          FROM (
            SELECT me.name, me.id
              FROM owners me
            LIMIT ?,?
          ) me
          LEFT JOIN books books
            ON books.owner = me.id
        ORDER BY books.owner
      )',
      [
        [ { sqlt_datatype => 'integer' } => 1 ],
        [ { sqlt_datatype => 'integer' } => 3 ],
      ]
    ],
  },

  SkipFirst => {
    ordered_limit_offset => [
      '(
        SELECT SKIP ? FIRST ? me.id, owner.id, owner.name, ? * ?, ?
          FROM books me
          JOIN owners owner
            ON owner.id = me.owner
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
    limit_offset_prefetch => [
      '(
        SELECT me.name, books.id, books.source, books.owner, books.title, books.price
          FROM (
            SELECT SKIP ? FIRST ? me.name, me.id
              FROM owners me
          ) me
          LEFT JOIN books books
            ON books.owner = me.id
        ORDER BY books.owner
      )',
      [
        [ { sqlt_datatype => 'integer' } => 1 ],
        [ { sqlt_datatype => 'integer' } => 3 ],
      ]
    ],
  },

  FirstSkip => {
    ordered_limit_offset => [
      '(
        SELECT FIRST ? SKIP ? me.id, owner.id, owner.name, ? * ?, ?
          FROM books me
          JOIN owners owner
            ON owner.id = me.owner
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
    limit_offset_prefetch => [
      '(
        SELECT me.name, books.id, books.source, books.owner, books.title, books.price
          FROM (
            SELECT FIRST ? SKIP ? me.name, me.id
              FROM owners me
          ) me
          LEFT JOIN books books
            ON books.owner = me.id
        ORDER BY books.owner
      )',
      [
        [ { sqlt_datatype => 'integer' } => 3 ],
        [ { sqlt_datatype => 'integer' } => 1 ],
      ]
    ],
  },

  RowNumberOver => do {
    my $unordered_sql = '(
      SELECT me.id, owner__id, owner__name, bar, baz
        FROM (
          SELECT me.id, owner__id, owner__name, bar, baz, ROW_NUMBER() OVER() AS rno__row__index
            FROM (
              SELECT me.id, owner.id AS owner__id, owner.name AS owner__name, ? * ? AS bar, ? AS baz
                FROM books me
                JOIN owners owner
                  ON owner.id = me.owner
              WHERE source != ? AND me.title = ? AND source = ?
              GROUP BY avg(me.id / ?)
              HAVING ?
            ) me
      ) me
      WHERE rno__row__index >= ? AND rno__row__index <= ?
    )';

    my $ordered_sql = '(
      SELECT me.id, owner__id, owner__name, bar, baz
        FROM (
          SELECT me.id, owner__id, owner__name, bar, baz, ROW_NUMBER() OVER( ORDER BY ORDER__BY__001, ORDER__BY__002 ) AS rno__row__index
            FROM (
              SELECT me.id, owner.id AS owner__id, owner.name AS owner__name, ? * ? AS bar, ? AS baz,
                     ? / ? AS ORDER__BY__001, ? AS ORDER__BY__002
                FROM books me
                JOIN owners owner
                  ON owner.id = me.owner
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
      limit_offset_prefetch => [
        '(
          SELECT me.name, books.id, books.source, books.owner, books.title, books.price
            FROM (
              SELECT me.name, me.id
                FROM (
                  SELECT me.name, me.id, ROW_NUMBER() OVER() AS rno__row__index
                  FROM (
                    SELECT me.name, me.id  FROM owners me
                  ) me
                ) me
              WHERE rno__row__index >= ? AND rno__row__index <= ?
            ) me
            LEFT JOIN books books
              ON books.owner = me.id
          ORDER BY books.owner
        )',
        [
          [ { sqlt_datatype => 'integer' } => 2 ],
          [ { sqlt_datatype => 'integer' } => 4 ],
        ]
      ],
    };
  },

  RowNum => do {
    my $limit_sql = sub {
      sprintf '(
        SELECT me.id, owner__id, owner__name, bar, baz
          FROM (
            SELECT me.id, owner.id AS owner__id, owner.name AS owner__name, ? * ? AS bar, ? AS baz
              FROM books me
              JOIN owners owner
                ON owner.id = me.owner
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
          SELECT me.id, owner__id, owner__name, bar, baz
            FROM (
              SELECT me.id, owner__id, owner__name, bar, baz, ROWNUM rownum__index
                FROM (
                  SELECT me.id, owner.id AS owner__id, owner.name AS owner__name, ? * ? AS bar, ? AS baz
                    FROM books me
                    JOIN owners owner
                      ON owner.id = me.owner
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
          SELECT me.id, owner__id, owner__name, bar, baz
            FROM (
              SELECT me.id, owner__id, owner__name, bar, baz, ROWNUM rownum__index
                FROM (
                  SELECT me.id, owner.id AS owner__id, owner.name AS owner__name, ? * ? AS bar, ? AS baz
                    FROM books me
                    JOIN owners owner
                      ON owner.id = me.owner
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
      limit_offset_prefetch => [
        '(
          SELECT me.name, books.id, books.source, books.owner, books.title, books.price
            FROM (
              SELECT me.name, me.id
                FROM (
                  SELECT me.name, me.id, ROWNUM rownum__index
                    FROM (
                      SELECT me.name, me.id
                        FROM owners me
                    ) me
                ) me WHERE rownum__index BETWEEN ? AND ?
            ) me
            LEFT JOIN books books
              ON books.owner = me.id
          ORDER BY books.owner
        )',
        [
          [ { sqlt_datatype => 'integer' } => 2 ],
          [ { sqlt_datatype => 'integer' } => 4 ],
        ]
      ],
    };
  },

  FetchFirst => {
    limit => [
      '(
        SELECT me.id, owner.id, owner.name, ? * ?, ?
          FROM books me
          JOIN owners owner
            ON owner.id = me.owner
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
        SELECT me.id, owner__id, owner__name, bar, baz
          FROM (
            SELECT me.id, owner.id AS owner__id, owner.name AS owner__name, ? * ? AS bar, ? AS baz
              FROM books me
              JOIN owners owner
                ON owner.id = me.owner
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
        SELECT me.id, owner.id, owner.name, ? * ?, ?
          FROM books me
          JOIN owners owner
            ON owner.id = me.owner
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
        SELECT me.id, owner__id, owner__name, bar, baz
          FROM (
            SELECT me.id, owner__id, owner__name, bar, baz, ORDER__BY__001, ORDER__BY__002
              FROM (
                SELECT me.id, owner.id AS owner__id, owner.name AS owner__name, ? * ? AS bar, ? AS baz, ? / ? AS ORDER__BY__001, ? AS ORDER__BY__002
                  FROM books me
                  JOIN owners owner
                    ON owner.id = me.owner
                WHERE source != ? AND me.title = ? AND source = ?
                GROUP BY avg(me.id / ?)
                HAVING ?
                ORDER BY ? / ?, ?
                FETCH FIRST 7 ROWS ONLY
              ) me
            ORDER BY ORDER__BY__001 DESC, ORDER__BY__002 DESC
            FETCH FIRST 4 ROWS ONLY
          ) me
        ORDER BY ORDER__BY__001, ORDER__BY__002
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
    limit_offset_prefetch => [
      '(
        SELECT me.name, books.id, books.source, books.owner, books.title, books.price
          FROM (
            SELECT me.name, me.id
              FROM (
                SELECT me.name, me.id
                  FROM owners me
                ORDER BY me.id
                FETCH FIRST 4 ROWS ONLY
              ) me
              ORDER BY me.id DESC
            FETCH FIRST 3 ROWS ONLY
          ) me
          LEFT JOIN books books
            ON books.owner = me.id
        ORDER BY books.owner
      )',
      [],
    ],
  },

  Top => {
    limit => [
      '(
        SELECT TOP 4 me.id, owner.id, owner.name, ? * ?, ?
          FROM books me
          JOIN owners owner
            ON owner.id = me.owner
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
        SELECT TOP 4 me.id, owner__id, owner__name, bar, baz
          FROM (
            SELECT TOP 7 me.id, owner.id AS owner__id, owner.name AS owner__name, ? * ? AS bar, ? AS baz
              FROM books me
              JOIN owners owner
                ON owner.id = me.owner
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
        SELECT TOP 4 me.id, owner.id, owner.name, ? * ?, ?
          FROM books me
          JOIN owners owner
            ON owner.id = me.owner
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
        SELECT me.id, owner__id, owner__name, bar, baz
          FROM (
            SELECT TOP 4 me.id, owner__id, owner__name, bar, baz, ORDER__BY__001, ORDER__BY__002
              FROM (
                SELECT TOP 7 me.id, owner.id AS owner__id, owner.name AS owner__name, ? * ? AS bar, ? AS baz, ? / ? AS ORDER__BY__001, ? AS ORDER__BY__002
                  FROM books me
                  JOIN owners owner
                    ON owner.id = me.owner
                WHERE source != ? AND me.title = ? AND source = ?
                GROUP BY avg(me.id / ?)
                HAVING ?
                ORDER BY ? / ?, ?
              ) me
            ORDER BY ORDER__BY__001 DESC, ORDER__BY__002 DESC
          ) me
        ORDER BY ORDER__BY__001, ORDER__BY__002
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
    limit_offset_prefetch => [
      '(
        SELECT me.name, books.id, books.source, books.owner, books.title, books.price
          FROM (
            SELECT TOP 3 me.name, me.id
              FROM (
                SELECT TOP 4 me.name, me.id
                  FROM owners me
                ORDER BY me.id
              ) me
              ORDER BY me.id DESC
          ) me
          LEFT JOIN books books
            ON books.owner = me.id
        ORDER BY books.owner
      )',
      [],
    ],
  },

  GenericSubQ => {
    limit => [
      '(
        SELECT me.id, owner__id, owner__name, bar, baz
          FROM (
            SELECT me.id, owner.id AS owner__id, owner.name AS owner__name, ? * ? AS bar, ? AS baz
              FROM books me
              JOIN owners owner
                ON owner.id = me.owner
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
        SELECT me.id, owner__id, owner__name, bar, baz
          FROM (
            SELECT me.id, owner.id AS owner__id, owner.name AS owner__name, ? * ? AS bar, ? AS baz
              FROM books me
              JOIN owners owner
                ON owner.id = me.owner
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
    limit_offset_prefetch => [
      '(
        SELECT me.name, books.id, books.source, books.owner, books.title, books.price
          FROM (
            SELECT me.name, me.id
              FROM (
                SELECT me.name, me.id  FROM owners me
              ) me
            WHERE (
              SELECT COUNT(*)
                FROM owners rownum__emulation
              WHERE rownum__emulation.id < me.id
            ) BETWEEN ? AND ?
            ORDER BY me.id
          ) me
          LEFT JOIN books books
            ON books.owner = me.id
        ORDER BY me.id, books.owner
      )',
      [
        [ { sqlt_datatype => 'integer' } => 1 ],
        [ { sqlt_datatype => 'integer' } => 3 ],
      ],
    ],
  }
};

for my $limtype (sort keys %$tests) {

  Test::Builder->new->is_passing or exit;

  delete $schema->storage->_sql_maker->{_cached_syntax};
  $schema->storage->_sql_maker->limit_dialect ($limtype);

  # chained search is necessary to exercise the recursive {where} parser
  my $rs = $schema->resultset('BooksInLibrary')->search({ 'me.title' => { '=' => 'kama sutra' } })->search({ source => { '!=', 'Study' } }, {
    columns => [ { identifier => 'me.id' }, 'owner.id', 'owner.name' ], # people actually do that. BLEH!!! :)
    join => 'owner',  # single-rel manual prefetch
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

  # complex prefetch on partial-fetch root with limit
  my $pref_rs = $schema->resultset('Owners')->search({}, {
    rows => 3,
    offset => 1,
    columns => 'name',  # only the owner name, still prefetch all the books
    prefetch => 'books',
    ($limtype =~ /GenericSubQ/ ? ( order_by => 'me.id' ) : () ),  # needs a simple-column stable order to be happy
  });

  is_same_sql_bind (
    $pref_rs->as_query,
    @{$tests->{$limtype}{limit_offset_prefetch}},
    "$limtype: Prefetch with limit+offset",
  ) if $tests->{$limtype}{limit_offset_prefetch};

  # we can actually run the query
  if ($limtype eq $native_limit_dialect or $limtype eq 'GenericSubQ') {
    lives_ok { is ($pref_rs->all, 1, 'Expected count of objects on limtied prefetch') }
      "Complex limited prefetch works with supported limit $limtype"
  }
}

done_testing;
