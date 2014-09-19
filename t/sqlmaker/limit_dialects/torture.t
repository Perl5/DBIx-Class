use strict;
use warnings;

use Test::More;
use Test::Exception;
use Storable 'dclone';
use lib qw(t/lib);
use DBICTest ':DiffSQL';

my $schema = DBICTest->init_schema;
my $native_limit_dialect = $schema->storage->sql_maker->{limit_dialect};

my $where_string = 'me.title = ? AND source != ? AND source = ?';

my @where_bind = (
  [ {} => 'kama sutra' ],
  [ {} => 'Study' ],
  [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' } => 'Library' ],
);
my @select_bind = (
  [ { sqlt_datatype => 'numeric' } => 11 ],
  [ {} => 12 ],
  [ { sqlt_datatype => 'integer', dbic_colname => 'me.id' } => 13 ],
);
my @group_bind = (
  [ {} => 21 ],
);
my @having_bind = (
  [ {} => 31 ],
);
my @order_bind = (
  [ { sqlt_datatype => 'int' } => 1 ],
  [ { sqlt_datatype => 'varchar', dbic_colname => 'name', sqlt_size => 100 } => 2 ],
  [ {} => 3 ],
);

my $tests = {

  LimitOffset => {
    limit_plain => [
      "( SELECT me.artistid FROM artist me LIMIT ? )",
      [
        [ { sqlt_datatype => 'integer' } => 5 ]
      ],
    ],
    limit => [
      "(
        SELECT me.id, owner.id, owner.name, ? * ?, ?
          FROM books me
          JOIN owners owner
            ON owner.id = me.owner
        WHERE $where_string
        GROUP BY (me.id / ?), owner.id
        HAVING ?
        LIMIT ?
      )",
      [
        @select_bind,
        @where_bind,
        @group_bind,
        @having_bind,
        [ { sqlt_datatype => 'integer' } => 4 ],
      ],
    ],
    limit_offset => [
      "(
        SELECT me.id, owner.id, owner.name, ? * ?, ?
          FROM books me
          JOIN owners owner
            ON owner.id = me.owner
        WHERE $where_string
        GROUP BY (me.id / ?), owner.id
        HAVING ?
        LIMIT ?
        OFFSET ?
      )",
      [
        @select_bind,
        @where_bind,
        @group_bind,
        @having_bind,
        [ { sqlt_datatype => 'integer' } => 4 ],
        [ { sqlt_datatype => 'integer' } => 3 ],
      ],
    ],
    ordered_limit => [
      "(
        SELECT me.id, owner.id, owner.name, ? * ?, ?
          FROM books me
          JOIN owners owner
            ON owner.id = me.owner
        WHERE $where_string
        GROUP BY (me.id / ?), owner.id
        HAVING ?
        ORDER BY ? / ?, ?
        LIMIT ?
      )",
      [
        @select_bind,
        @where_bind,
        @group_bind,
        @having_bind,
        @order_bind,
        [ { sqlt_datatype => 'integer' } => 4 ],
      ]
    ],
    ordered_limit_offset => [
      "(
        SELECT me.id, owner.id, owner.name, ? * ?, ?
          FROM books me
          JOIN owners owner
            ON owner.id = me.owner
        WHERE $where_string
        GROUP BY (me.id / ?), owner.id
        HAVING ?
        ORDER BY ? / ?, ?
        LIMIT ?
        OFFSET ?
      )",
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
      "(
        SELECT me.name, books.id, books.source, books.owner, books.title, books.price
          FROM (
            SELECT me.name, me.id
              FROM owners me
            LIMIT ? OFFSET ?
          ) me
          LEFT JOIN books books
            ON books.owner = me.id
      )",
      [
        [ { sqlt_datatype => 'integer' } => 3 ],
        [ { sqlt_datatype => 'integer' } => 1 ],
      ]
    ],
  },

  LimitXY => {
    limit_plain => [
      "( SELECT me.artistid FROM artist me LIMIT ? )",
      [
        [ { sqlt_datatype => 'integer' } => 5 ]
      ],
    ],
    ordered_limit_offset => [
      "(
        SELECT me.id, owner.id, owner.name, ? * ?, ?
          FROM books me
          JOIN owners owner
            ON owner.id = me.owner
        WHERE $where_string
        GROUP BY (me.id / ?), owner.id
        HAVING ?
        ORDER BY ? / ?, ?
        LIMIT ?, ?
      )",
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
      "(
        SELECT me.name, books.id, books.source, books.owner, books.title, books.price
          FROM (
            SELECT me.name, me.id
              FROM owners me
            LIMIT ?,?
          ) me
          LEFT JOIN books books
            ON books.owner = me.id
      )",
      [
        [ { sqlt_datatype => 'integer' } => 1 ],
        [ { sqlt_datatype => 'integer' } => 3 ],
      ]
    ],
  },

  SkipFirst => {
    limit_plain => [
      "( SELECT FIRST ? me.artistid FROM artist me )",
      [
        [ { sqlt_datatype => 'integer' } => 5 ]
      ],
    ],
    ordered_limit_offset => [
      "(
        SELECT SKIP ? FIRST ? me.id, owner.id, owner.name, ? * ?, ?
          FROM books me
          JOIN owners owner
            ON owner.id = me.owner
        WHERE $where_string
        GROUP BY (me.id / ?), owner.id
        HAVING ?
        ORDER BY ? / ?, ?
      )",
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
      "(
        SELECT me.name, books.id, books.source, books.owner, books.title, books.price
          FROM (
            SELECT SKIP ? FIRST ? me.name, me.id
              FROM owners me
          ) me
          LEFT JOIN books books
            ON books.owner = me.id
      )",
      [
        [ { sqlt_datatype => 'integer' } => 1 ],
        [ { sqlt_datatype => 'integer' } => 3 ],
      ]
    ],
  },

  FirstSkip => {
    limit_plain => [
      "( SELECT FIRST ? me.artistid FROM artist me )",
      [
        [ { sqlt_datatype => 'integer' } => 5 ]
      ],
    ],
    ordered_limit_offset => [
      "(
        SELECT FIRST ? SKIP ? me.id, owner.id, owner.name, ? * ?, ?
          FROM books me
          JOIN owners owner
            ON owner.id = me.owner
        WHERE $where_string
        GROUP BY (me.id / ?), owner.id
        HAVING ?
        ORDER BY ? / ?, ?
      )",
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
      "(
        SELECT me.name, books.id, books.source, books.owner, books.title, books.price
          FROM (
            SELECT FIRST ? SKIP ? me.name, me.id
              FROM owners me
          ) me
          LEFT JOIN books books
            ON books.owner = me.id
      )",
      [
        [ { sqlt_datatype => 'integer' } => 3 ],
        [ { sqlt_datatype => 'integer' } => 1 ],
      ]
    ],
  },

  RowNumberOver => do {
    my $unordered_sql = "(
      SELECT me.id, owner__id, owner__name, bar, baz
        FROM (
          SELECT me.id, owner__id, owner__name, bar, baz, ROW_NUMBER() OVER() AS rno__row__index
            FROM (
              SELECT me.id, owner.id AS owner__id, owner.name AS owner__name, ? * ? AS bar, ? AS baz
                FROM books me
                JOIN owners owner
                  ON owner.id = me.owner
              WHERE $where_string
              GROUP BY (me.id / ?), owner.id
              HAVING ?
            ) me
      ) me
      WHERE rno__row__index >= ? AND rno__row__index <= ?
    )";

    my $ordered_sql = "(
      SELECT me.id, owner__id, owner__name, bar, baz
        FROM (
          SELECT me.id, owner__id, owner__name, bar, baz, ROW_NUMBER() OVER( ORDER BY ORDER__BY__001, ORDER__BY__002 ) AS rno__row__index
            FROM (
              SELECT me.id, owner.id AS owner__id, owner.name AS owner__name, ? * ? AS bar, ? AS baz,
                     ? / ? AS ORDER__BY__001, ? AS ORDER__BY__002
                FROM books me
                JOIN owners owner
                  ON owner.id = me.owner
              WHERE $where_string
              GROUP BY (me.id / ?), owner.id
              HAVING ?
            ) me
      ) me
      WHERE rno__row__index >= ? AND rno__row__index <= ?
    )";

    {
      limit_plain => [
        "(
          SELECT me.artistid
            FROM (
              SELECT me.artistid, ROW_NUMBER() OVER(  ) AS rno__row__index
                FROM (
                  SELECT me.artistid
                    FROM artist me
                ) me
            ) me
          WHERE rno__row__index >= ? AND rno__row__index <= ?
        )",
        [
          [ { sqlt_datatype => 'integer' } => 1 ],
          [ { sqlt_datatype => 'integer' } => 5 ],
        ],
      ],
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
        "(
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
        )",
        [
          [ { sqlt_datatype => 'integer' } => 2 ],
          [ { sqlt_datatype => 'integer' } => 4 ],
        ]
      ],
    };
  },

  RowNum => do {
    my $limit_sql = sub {
      sprintf "(
        SELECT me.id, owner__id, owner__name, bar, baz
          FROM (
            SELECT me.id, owner.id AS owner__id, owner.name AS owner__name, ? * ? AS bar, ? AS baz
              FROM books me
              JOIN owners owner
                ON owner.id = me.owner
            WHERE $where_string
            GROUP BY (me.id / ?), owner.id
            HAVING ?
            %s
          ) me
        WHERE ROWNUM <= ?
      )", $_[0] || '';
    };

    {
      limit_plain => [
        "(
          SELECT me.artistid
            FROM (
              SELECT me.artistid
                FROM artist me
            ) me
          WHERE ROWNUM <= ?
        )",
        [
          [ { sqlt_datatype => 'integer' } => 5 ],
        ],
      ],
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
        "(
          SELECT me.id, owner__id, owner__name, bar, baz
            FROM (
              SELECT me.id, owner__id, owner__name, bar, baz, ROWNUM AS rownum__index
                FROM (
                  SELECT me.id, owner.id AS owner__id, owner.name AS owner__name, ? * ? AS bar, ? AS baz
                    FROM books me
                    JOIN owners owner
                      ON owner.id = me.owner
                  WHERE $where_string
                  GROUP BY (me.id / ?), owner.id
                  HAVING ?
                ) me
            ) me
          WHERE rownum__index BETWEEN ? AND ?
        )",
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
        "(
          SELECT me.id, owner__id, owner__name, bar, baz
            FROM (
              SELECT me.id, owner__id, owner__name, bar, baz, ROWNUM AS rownum__index
                FROM (
                  SELECT me.id, owner.id AS owner__id, owner.name AS owner__name, ? * ? AS bar, ? AS baz
                    FROM books me
                    JOIN owners owner
                      ON owner.id = me.owner
                  WHERE $where_string
                  GROUP BY (me.id / ?), owner.id
                  HAVING ?
                  ORDER BY ? / ?, ?
                ) me
              WHERE ROWNUM <= ?
            ) me
          WHERE rownum__index >= ?
        )",
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
        "(
          SELECT me.name, books.id, books.source, books.owner, books.title, books.price
            FROM (
              SELECT me.name, me.id
                FROM (
                  SELECT me.name, me.id, ROWNUM AS rownum__index
                    FROM (
                      SELECT me.name, me.id
                        FROM owners me
                    ) me
                ) me WHERE rownum__index BETWEEN ? AND ?
            ) me
            LEFT JOIN books books
              ON books.owner = me.id
        )",
        [
          [ { sqlt_datatype => 'integer' } => 2 ],
          [ { sqlt_datatype => 'integer' } => 4 ],
        ]
      ],
    };
  },

  FetchFirst => {
    limit_plain => [
      "( SELECT me.artistid FROM artist me FETCH FIRST 5 ROWS ONLY )",
      [],
    ],
    limit => [
      "(
        SELECT me.id, owner.id, owner.name, ? * ?, ?
          FROM books me
          JOIN owners owner
            ON owner.id = me.owner
        WHERE $where_string
        GROUP BY (me.id / ?), owner.id
        HAVING ?
        FETCH FIRST 4 ROWS ONLY
      )",
      [
        @select_bind,
        @where_bind,
        @group_bind,
        @having_bind,
      ],
    ],
    limit_offset => [
      "(
        SELECT me.id, owner__id, owner__name, bar, baz
          FROM (
            SELECT me.id, owner.id AS owner__id, owner.name AS owner__name, ? * ? AS bar, ? AS baz
              FROM books me
              JOIN owners owner
                ON owner.id = me.owner
            WHERE $where_string
            GROUP BY (me.id / ?), owner.id
            HAVING ?
            ORDER BY me.id
            FETCH FIRST 7 ROWS ONLY
          ) me
        ORDER BY me.id DESC
        FETCH FIRST 4 ROWS ONLY
      )",
      [
        @select_bind,
        @where_bind,
        @group_bind,
        @having_bind,
      ],
    ],
    ordered_limit => [
      "(
        SELECT me.id, owner.id, owner.name, ? * ?, ?
          FROM books me
          JOIN owners owner
            ON owner.id = me.owner
        WHERE $where_string
        GROUP BY (me.id / ?), owner.id
        HAVING ?
        ORDER BY ? / ?, ?
        FETCH FIRST 4 ROWS ONLY
      )",
      [
        @select_bind,
        @where_bind,
        @group_bind,
        @having_bind,
        @order_bind,
      ],
    ],
    ordered_limit_offset => [
      "(
        SELECT me.id, owner__id, owner__name, bar, baz
          FROM (
            SELECT me.id, owner__id, owner__name, bar, baz, ORDER__BY__001, ORDER__BY__002
              FROM (
                SELECT me.id, owner.id AS owner__id, owner.name AS owner__name, ? * ? AS bar, ? AS baz, ? / ? AS ORDER__BY__001, ? AS ORDER__BY__002
                  FROM books me
                  JOIN owners owner
                    ON owner.id = me.owner
                WHERE $where_string
                GROUP BY (me.id / ?), owner.id
                HAVING ?
                ORDER BY ? / ?, ?
                FETCH FIRST 7 ROWS ONLY
              ) me
            ORDER BY ORDER__BY__001 DESC, ORDER__BY__002 DESC
            FETCH FIRST 4 ROWS ONLY
          ) me
        ORDER BY ORDER__BY__001, ORDER__BY__002
      )",
      [
        @select_bind,
        @order_bind,
        @where_bind,
        @group_bind,
        @having_bind,
        @{ dclone \@order_bind },  # without this is_deeply throws a fit
      ],
    ],
    limit_offset_prefetch => [
      "(
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
      )",
      [],
    ],
  },

  Top => {
    limit_plain => [
      "( SELECT TOP 5 me.artistid FROM artist me )",
      [],
    ],
    limit => [
      "(
        SELECT TOP 4 me.id, owner.id, owner.name, ? * ?, ?
          FROM books me
          JOIN owners owner
            ON owner.id = me.owner
        WHERE $where_string
        GROUP BY (me.id / ?), owner.id
        HAVING ?
      )",
      [
        @select_bind,
        @where_bind,
        @group_bind,
        @having_bind,
      ],
    ],
    limit_offset => [
      "(
        SELECT TOP 4 me.id, owner__id, owner__name, bar, baz
          FROM (
            SELECT TOP 7 me.id, owner.id AS owner__id, owner.name AS owner__name, ? * ? AS bar, ? AS baz
              FROM books me
              JOIN owners owner
                ON owner.id = me.owner
            WHERE $where_string
            GROUP BY (me.id / ?), owner.id
            HAVING ?
            ORDER BY me.id
          ) me
        ORDER BY me.id DESC
      )",
      [
        @select_bind,
        @where_bind,
        @group_bind,
        @having_bind,
      ],
    ],
    ordered_limit => [
      "(
        SELECT TOP 4 me.id, owner.id, owner.name, ? * ?, ?
          FROM books me
          JOIN owners owner
            ON owner.id = me.owner
        WHERE $where_string
        GROUP BY (me.id / ?), owner.id
        HAVING ?
        ORDER BY ? / ?, ?
      )",
      [
        @select_bind,
        @where_bind,
        @group_bind,
        @having_bind,
        @order_bind,
      ],
    ],
    ordered_limit_offset => [
      "(
        SELECT me.id, owner__id, owner__name, bar, baz
          FROM (
            SELECT TOP 4 me.id, owner__id, owner__name, bar, baz, ORDER__BY__001, ORDER__BY__002
              FROM (
                SELECT TOP 7 me.id, owner.id AS owner__id, owner.name AS owner__name, ? * ? AS bar, ? AS baz, ? / ? AS ORDER__BY__001, ? AS ORDER__BY__002
                  FROM books me
                  JOIN owners owner
                    ON owner.id = me.owner
                WHERE $where_string
                GROUP BY (me.id / ?), owner.id
                HAVING ?
                ORDER BY ? / ?, ?
              ) me
            ORDER BY ORDER__BY__001 DESC, ORDER__BY__002 DESC
          ) me
        ORDER BY ORDER__BY__001, ORDER__BY__002
      )",
      [
        @select_bind,
        @order_bind,
        @where_bind,
        @group_bind,
        @having_bind,
        @{ dclone \@order_bind },  # without this is_deeply throws a fit
      ],
    ],
    limit_offset_prefetch => [
      "(
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
      )",
      [],
    ],
  },

  GenericSubQ => {
    limit_plain => [
      "(
        SELECT me.artistid
          FROM (
            SELECT me.artistid
              FROM artist me
          ) me
        WHERE
          (
            SELECT COUNT(*)
              FROM artist rownum__emulation
            WHERE rownum__emulation.artistid < me.artistid
          ) < ?
        ORDER BY me.artistid ASC
      )",
      [
        [ { sqlt_datatype => 'integer' } => 5 ]
      ],
    ],
    ordered_limit => [
      "(
        SELECT me.id, owner__id, owner__name, bar, baz
          FROM (
            SELECT me.id, owner.id AS owner__id, owner.name AS owner__name, ? * ? AS bar, ? AS baz, me.price
              FROM books me
              JOIN owners owner
                ON owner.id = me.owner
            WHERE $where_string
            GROUP BY (me.id / ?), owner.id
            HAVING ?
          ) me
        WHERE (
          SELECT COUNT( * )
            FROM books rownum__emulation
          WHERE
            ( me.price IS NULL AND rownum__emulation.price IS NOT NULL )
              OR
            (
              rownum__emulation.price > me.price
                AND
              me.price IS NOT NULL
                AND
              rownum__emulation.price IS NOT NULL
            )
              OR
            (
              (
                me.price = rownum__emulation.price
                 OR
                ( me.price IS NULL AND rownum__emulation.price IS NULL )
              )
                AND
              rownum__emulation.id < me.id
            )
          ) < ?
        ORDER BY me.price DESC, me.id ASC
      )",
      [
        @select_bind,
        @where_bind,
        @group_bind,
        @having_bind,
        [ { sqlt_datatype => 'integer' } => 4 ],
      ],
    ],
    ordered_limit_offset => [
      "(
        SELECT me.id, owner__id, owner__name, bar, baz
          FROM (
            SELECT me.id, owner.id AS owner__id, owner.name AS owner__name, ? * ? AS bar, ? AS baz, me.price
              FROM books me
              JOIN owners owner
                ON owner.id = me.owner
            WHERE $where_string
            GROUP BY (me.id / ?), owner.id
            HAVING ?
          ) me
        WHERE (
          SELECT COUNT( * )
            FROM books rownum__emulation
          WHERE
            ( me.price IS NULL AND rownum__emulation.price IS NOT NULL )
              OR
            (
              rownum__emulation.price > me.price
                AND
              me.price IS NOT NULL
                AND
              rownum__emulation.price IS NOT NULL
            )
              OR
            (
              (
                me.price = rownum__emulation.price
                 OR
                ( me.price IS NULL AND rownum__emulation.price IS NULL )
              )
                AND
              rownum__emulation.id < me.id
            )
          ) BETWEEN ? AND ?
        ORDER BY me.price DESC, me.id ASC
      )",
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
      "(
        SELECT me.name, books.id, books.source, books.owner, books.title, books.price
          FROM (
            SELECT me.name, me.id
              FROM (
                SELECT me.name, me.id
                  FROM owners me
              ) me
            WHERE
              (
                SELECT COUNT(*)
                  FROM owners rownum__emulation
                WHERE (
                  rownum__emulation.name < me.name
                    OR
                  (
                    me.name = rownum__emulation.name
                      AND
                    rownum__emulation.id > me.id
                  )
                )
              ) BETWEEN ? AND ?
            ORDER BY me.name ASC, me.id DESC
          ) me
          LEFT JOIN books books
            ON books.owner = me.id
        ORDER BY me.name ASC, me.id DESC
      )",
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

  # do the simplest thing possible first
  if ($tests->{$limtype}{limit_plain}) {
    is_same_sql_bind(
      $schema->resultset('Artist')->search(
        [ -and => [ {}, [] ], -or => [ {}, [] ] ],
        {
          columns => 'artistid',
          join => [ {}, [ [ {}, {} ] ], {} ],
          prefetch => [ [ [ {}, [] ], {} ], {}, [ {} ] ],
          order_by => ( $limtype eq 'GenericSubQ' ? 'artistid' : [] ),
          group_by => [],
          rows => 5,
          offset => 0,
        }
      )->as_query,
      @{$tests->{$limtype}{limit_plain}},
      "$limtype: Plain unordered ungrouped select with limit and no offset",
    )
  }

  # chained search is necessary to exercise the recursive {where} parser
  my $rs = $schema->resultset('BooksInLibrary')->search(
    { 'me.title' => { '=' => \[ '?', 'kama sutra' ] } }
  )->search(
    { source => { '!=', \[ '?', [ {} => 'Study' ] ] } },
    {
      columns => [ { identifier => 'me.id' }, 'owner.id', 'owner.name' ], # people actually do that. BLEH!!! :)
      join => 'owner',  # single-rel manual prefetch
      rows => 4,
      '+columns' => { bar => \['? * ?', [ \ 'numeric' => 11 ], 12 ], baz => \[ '?', [ 'me.id' => 13 ] ] },
      group_by => \[ '(me.id / ?), owner.id', 21 ],
      having => \[ '?', 31 ],
    }
  );

  #
  # not all tests run on all dialects (somewhere impossible, somewhere makes no sense)
  #
  my $can_run = ($limtype eq $native_limit_dialect or $limtype eq 'GenericSubQ');

  # only limit, no offset, no order
  if ($tests->{$limtype}{limit}) {
    lives_ok {
      is_same_sql_bind(
        $rs->as_query,
        @{$tests->{$limtype}{limit}},
        "$limtype: Unordered limit with select/group/having",
      );

      $rs->all if $can_run;
    } "Grouped limit under $limtype";
  }

  # limit + offset, no order
  if ($tests->{$limtype}{limit_offset}) {

    lives_ok {
      my $subrs = $rs->search({}, { offset => 3 });

      is_same_sql_bind(
        $subrs->as_query,
        @{$tests->{$limtype}{limit_offset}},
        "$limtype: Unordered limit+offset with select/group/having",
      );

      $subrs->all if $can_run;
    } "Grouped limit+offset runs under $limtype";
  }

  # order + limit, no offset
  $rs = $rs->search(undef, {
    order_by => ( $limtype =~ /GenericSubQ/
      ? [ { -desc => 'price' }, 'me.id', \[ 'owner.name + ?', 'bah' ] ] # needs a same-table stable order to be happy
      : [ \['? / ?', [ \ 'int' => 1 ], [ name => 2 ]], \[ '?', 3 ] ]
    ),
  });

  if ($tests->{$limtype}{ordered_limit}) {

    lives_ok {
      is_same_sql_bind(
        $rs->as_query,
        @{$tests->{$limtype}{ordered_limit}},
        "$limtype: Ordered limit with select/group/having",
      );

      $rs->all if $can_run;
    } "Grouped ordered limit runs under $limtype"
  }

  # order + limit + offset
  if ($tests->{$limtype}{ordered_limit_offset}) {
    lives_ok {
      my $subrs = $rs->search({}, { offset => 3 });

      is_same_sql_bind(
        $subrs->as_query,
        @{$tests->{$limtype}{ordered_limit_offset}},
        "$limtype: Ordered limit+offset with select/group/having",
      );

      $subrs->all if $can_run;
    } "Grouped ordered limit+offset runs under $limtype";
  }

  # complex prefetch on partial-fetch root with limit
  my $pref_rs = $schema->resultset('Owners')->search({}, {
    rows => 3,
    offset => 1,
    columns => 'name',  # only the owner name, still prefetch all the books
    prefetch => 'books',
    ($limtype !~ /GenericSubQ/ ? () : (
      # needs a same-table stable order to be happy
      order_by => [ { -asc => 'me.name' }, \ 'me.id DESC' ]
    )),
  });

  lives_ok {
    is_same_sql_bind (
      $pref_rs->as_query,
      @{$tests->{$limtype}{limit_offset_prefetch}},
      "$limtype: Prefetch with limit+offset",
    ) if $tests->{$limtype}{limit_offset_prefetch};

    is ($pref_rs->all, 1, 'Expected count of objects on limited prefetch')
      if $can_run;
  } "Complex limited prefetch runs under $limtype";
}

done_testing;
