use strict;
use warnings;

use Test::More;
use lib qw(t/lib);

use DBIx::Class::Optional::Dependencies;
plan skip_all => 'Test needs ' . DBIx::Class::Optional::Dependencies->req_missing_for ('id_shortener')
  unless DBIx::Class::Optional::Dependencies->req_ok_for ('id_shortener');

use DBICTest::Schema::Artist;
BEGIN {
  DBICTest::Schema::Artist->add_column('parentid');

  DBICTest::Schema::Artist->has_many(
    children => 'DBICTest::Schema::Artist',
    { 'foreign.parentid' => 'self.artistid' }
  );

  DBICTest::Schema::Artist->belongs_to(
    parent => 'DBICTest::Schema::Artist',
    { 'foreign.artistid' => 'self.parentid' }
  );
}

use DBICTest ':DiffSQL';

my $ROWS = DBIx::Class::SQLMaker::ClassicExtensions->__rows_bindtype;
my $TOTAL = DBIx::Class::SQLMaker::ClassicExtensions->__total_bindtype;

for my $q ( '', '"' ) {

  my $schema = DBICTest->init_schema(
    storage_type => 'DBIx::Class::Storage::DBI::Oracle::Generic',
    no_deploy => 1,
    quote_char => $q,
  );

  # select the whole tree
  {
    my $rs = $schema->resultset('Artist')->search({}, {
      start_with => { name => 'root' },
      connect_by => { parentid => { -prior => { -ident => 'artistid' } } },
    });

    is_same_sql_bind (
      $rs->as_query,
      "(
        SELECT ${q}me${q}.${q}artistid${q}, ${q}me${q}.${q}name${q}, ${q}me${q}.${q}rank${q}, ${q}me${q}.${q}charfield${q}, ${q}me${q}.${q}parentid${q}
          FROM ${q}artist${q} ${q}me${q}
        START WITH ${q}name${q} = ?
        CONNECT BY ${q}parentid${q} = PRIOR ${q}artistid${q}
      )",
      [ [ { 'sqlt_datatype' => 'varchar', 'dbic_colname' => 'name', 'sqlt_size' => 100 }
            => 'root'] ],
    );

    is_same_sql_bind (
      $rs->count_rs->as_query,
      "(
        SELECT COUNT( * )
          FROM ${q}artist${q} ${q}me${q}
        START WITH ${q}name${q} = ?
        CONNECT BY ${q}parentid${q} = PRIOR ${q}artistid${q}
      )",
      [ [ { 'sqlt_datatype' => 'varchar', 'dbic_colname' => 'name', 'sqlt_size' => 100 }
            => 'root'] ],
    );
  }

  # use order siblings by statement
  {
    my $rs = $schema->resultset('Artist')->search({}, {
      start_with => { name => 'root' },
      connect_by => { parentid => { -prior => { -ident =>  'artistid' } } },
      order_siblings_by => { -desc => 'name' },
    });

    is_same_sql_bind (
      $rs->as_query,
      "(
        SELECT ${q}me${q}.${q}artistid${q}, ${q}me${q}.${q}name${q}, ${q}me${q}.${q}rank${q}, ${q}me${q}.${q}charfield${q}, ${q}me${q}.${q}parentid${q}
          FROM ${q}artist${q} ${q}me${q}
        START WITH ${q}name${q} = ?
        CONNECT BY ${q}parentid${q} = PRIOR ${q}artistid${q}
        ORDER SIBLINGS BY ${q}name${q} DESC
      )",
      [ [ { 'sqlt_datatype' => 'varchar', 'dbic_colname' => 'name', 'sqlt_size' => 100 }
            => 'root'] ],
    );
  }

  # get the root node
  {
    my $rs = $schema->resultset('Artist')->search({ parentid => undef }, {
      start_with => { name => 'root' },
      connect_by => { parentid => { -prior => { -ident => 'artistid' } } },
    });

    is_same_sql_bind (
      $rs->as_query,
      "(
        SELECT ${q}me${q}.${q}artistid${q}, ${q}me${q}.${q}name${q}, ${q}me${q}.${q}rank${q}, ${q}me${q}.${q}charfield${q}, ${q}me${q}.${q}parentid${q}
          FROM ${q}artist${q} ${q}me${q}
        WHERE ( ${q}parentid${q} IS NULL )
        START WITH ${q}name${q} = ?
        CONNECT BY ${q}parentid${q} = PRIOR ${q}artistid${q}
      )",
      [ [ { 'sqlt_datatype' => 'varchar', 'dbic_colname' => 'name', 'sqlt_size' => 100 }
            => 'root'] ],
    );
  }

  # combine a connect by with a join
  {
    my $rs = $schema->resultset('Artist')->search(
      {'cds.title' => { -like => '%cd'} },
      {
        join => 'cds',
        start_with => { 'me.name' => 'root' },
        connect_by => { parentid => { -prior => { -ident => 'artistid' } } },
      }
    );

    is_same_sql_bind (
      $rs->as_query,
      "(
        SELECT ${q}me${q}.${q}artistid${q}, ${q}me${q}.${q}name${q}, ${q}me${q}.${q}rank${q}, ${q}me${q}.${q}charfield${q}, ${q}me${q}.${q}parentid${q}
          FROM ${q}artist${q} ${q}me${q}
          LEFT JOIN cd ${q}cds${q} ON ${q}cds${q}.${q}artist${q} = ${q}me${q}.${q}artistid${q}
        WHERE ( ${q}cds${q}.${q}title${q} LIKE ? )
        START WITH ${q}me${q}.${q}name${q} = ?
        CONNECT BY ${q}parentid${q} = PRIOR ${q}artistid${q}
      )",
      [
        [ { 'sqlt_datatype' => 'varchar', 'dbic_colname' => 'cds.title', 'sqlt_size' => 100 }
            => '%cd'],
        [ { 'sqlt_datatype' => 'varchar', 'dbic_colname' => 'me.name', 'sqlt_size' => 100 }
            => 'root'],
      ],
    );

    is_same_sql_bind (
      $rs->count_rs->as_query,
      "(
        SELECT COUNT( * )
          FROM ${q}artist${q} ${q}me${q}
          LEFT JOIN cd ${q}cds${q} ON ${q}cds${q}.${q}artist${q} = ${q}me${q}.${q}artistid${q}
        WHERE ( ${q}cds${q}.${q}title${q} LIKE ? )
        START WITH ${q}me${q}.${q}name${q} = ?
        CONNECT BY ${q}parentid${q} = PRIOR ${q}artistid${q}
      )",
      [
        [ { 'sqlt_datatype' => 'varchar', 'dbic_colname' => 'cds.title', 'sqlt_size' => 100 }
            => '%cd'],
        [ { 'sqlt_datatype' => 'varchar', 'dbic_colname' => 'me.name', 'sqlt_size' => 100 }
              => 'root'],
      ],
    );
  }

  # combine a connect by with order_by
  {
    my $rs = $schema->resultset('Artist')->search({}, {
      start_with => { name => 'root' },
      connect_by => { parentid => { -prior => { -ident => 'artistid' } } },
      order_by => { -asc => [ 'LEVEL', 'name' ] },
    });

    is_same_sql_bind (
      $rs->as_query,
      "(
        SELECT ${q}me${q}.${q}artistid${q}, ${q}me${q}.${q}name${q}, ${q}me${q}.${q}rank${q}, ${q}me${q}.${q}charfield${q}, ${q}me${q}.${q}parentid${q}
          FROM ${q}artist${q} ${q}me${q}
        START WITH ${q}name${q} = ?
        CONNECT BY ${q}parentid${q} = PRIOR ${q}artistid${q}
        ORDER BY ${q}LEVEL${q} ASC, ${q}name${q} ASC
      )",
      [
        [ { 'sqlt_datatype' => 'varchar', 'dbic_colname' => 'name', 'sqlt_size' => 100 }
            => 'root'],
      ],
    );
  }

  # limit a connect by
  {
    my $rs = $schema->resultset('Artist')->search({}, {
      start_with => { name => 'root' },
      connect_by => { parentid => { -prior => { -ident => 'artistid' } } },
      order_by => [ { -asc => 'name' }, {  -desc => 'artistid' } ],
      rows => 2,
    });

    is_same_sql_bind (
      $rs->as_query,
      "(
        SELECT ${q}me${q}.${q}artistid${q}, ${q}me${q}.${q}name${q}, ${q}me${q}.${q}rank${q}, ${q}me${q}.${q}charfield${q}, ${q}me${q}.${q}parentid${q}
          FROM (
            SELECT ${q}me${q}.${q}artistid${q}, ${q}me${q}.${q}name${q}, ${q}me${q}.${q}rank${q}, ${q}me${q}.${q}charfield${q}, ${q}me${q}.${q}parentid${q}
              FROM ${q}artist${q} ${q}me${q}
            START WITH ${q}name${q} = ?
            CONNECT BY ${q}parentid${q} = PRIOR ${q}artistid${q}
            ORDER BY ${q}name${q} ASC, ${q}artistid${q} DESC
          ) ${q}me${q}
        WHERE ROWNUM <= ?
      )",
      [
        [ { 'sqlt_datatype' => 'varchar', 'dbic_colname' => 'name', 'sqlt_size' => 100 }
            => 'root'], [ $ROWS => 2 ],
      ],
    );

    is_same_sql_bind (
      $rs->count_rs->as_query,
      "(
        SELECT COUNT( * )
          FROM (
            SELECT ${q}me${q}.${q}artistid${q}
              FROM (
                SELECT ${q}me${q}.${q}artistid${q}
                  FROM ${q}artist${q} ${q}me${q}
                START WITH ${q}name${q} = ?
                CONNECT BY ${q}parentid${q} = PRIOR ${q}artistid${q}
              ) ${q}me${q}
            WHERE ROWNUM <= ?
          ) ${q}me${q}
      )",
      [
        [ { 'sqlt_datatype' => 'varchar', 'dbic_colname' => 'name', 'sqlt_size' => 100 }
            => 'root'],
        [ $ROWS => 2 ],
      ],
    );
  }

  # combine a connect_by with group_by and having
  # add some bindvals to make sure things still work
  {
    my $rs = $schema->resultset('Artist')->search({}, {
      select => \[ 'COUNT(rank) + ?', [ __cbind => 3 ] ],
      as => 'cnt',
      start_with => { name => 'root' },
      connect_by => { parentid => { -prior => { -ident => 'artistid' } } },
      group_by => \[ 'rank + ? ', [ __gbind =>  1] ],
      having => \[ 'count(rank) < ?', [ cnt => 2 ] ],
    });

    is_same_sql_bind (
      $rs->as_query,
      "(
        SELECT COUNT(rank) + ?
          FROM ${q}artist${q} ${q}me${q}
        START WITH ${q}name${q} = ?
        CONNECT BY ${q}parentid${q} = PRIOR ${q}artistid${q}
        GROUP BY( rank + ? )
        HAVING count(rank) < ?
      )",
      [
        [ { dbic_colname => '__cbind' }
            => 3 ],
        [ { 'sqlt_datatype' => 'varchar', 'dbic_colname' => 'name', 'sqlt_size' => 100 }
            => 'root'],
        [ { dbic_colname => '__gbind' }
            => 1 ],
        [ { dbic_colname => 'cnt' }
            => 2 ],
      ],
    );
  }

  # select the whole cycle tree with nocylce
  {
    my $rs = $schema->resultset('Artist')->search({}, {
      start_with => { name => 'cycle-root' },
      '+select'  => \ 'CONNECT_BY_ISCYCLE',
      '+as'      => [ 'connector' ],
      connect_by_nocycle => { parentid => { -prior => { -ident => 'artistid' } } },
    });

    is_same_sql_bind (
      $rs->as_query,
      "(
        SELECT ${q}me${q}.${q}artistid${q}, ${q}me${q}.${q}name${q}, ${q}me${q}.${q}rank${q}, ${q}me${q}.${q}charfield${q}, ${q}me${q}.${q}parentid${q}, CONNECT_BY_ISCYCLE
          FROM ${q}artist${q} ${q}me${q}
        START WITH ${q}name${q} = ?
        CONNECT BY NOCYCLE ${q}parentid${q} = PRIOR ${q}artistid${q}
      )",
      [
        [ { 'sqlt_datatype' => 'varchar', 'dbic_colname' => 'name', 'sqlt_size' => 100 }
            => 'cycle-root'],
      ],
    );

    is_same_sql_bind (
      $rs->count_rs->as_query,
      "(
        SELECT COUNT( * )
          FROM ${q}artist${q} ${q}me${q}
        START WITH ${q}name${q} = ?
        CONNECT BY NOCYCLE ${q}parentid${q} = PRIOR ${q}artistid${q}
      )",
      [
        [ { 'sqlt_datatype' => 'varchar', 'dbic_colname' => 'name', 'sqlt_size' => 100 }
            => 'cycle-root'],
      ],
    );
  }
}

done_testing;
