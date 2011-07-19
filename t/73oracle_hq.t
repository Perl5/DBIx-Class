use strict;
use warnings;

use Test::Exception;
use Test::More;
use DBIx::Class::Optional::Dependencies ();
use lib qw(t/lib);
use DBIC::SqlMakerTest;

use DBIx::Class::SQLMaker::LimitDialects;
my $ROWS = DBIx::Class::SQLMaker::LimitDialects->__rows_bindtype,
my $TOTAL = DBIx::Class::SQLMaker::LimitDialects->__total_bindtype,

$ENV{NLS_SORT} = "BINARY";
$ENV{NLS_COMP} = "BINARY";
$ENV{NLS_LANG} = "AMERICAN";

my ($dsn,  $user,  $pass)  = @ENV{map { "DBICTEST_ORA_${_}" }  qw/DSN USER PASS/};

plan skip_all => 'Set $ENV{DBICTEST_ORA_DSN}, _USER and _PASS to run this test.'
 unless ($dsn && $user && $pass);

plan skip_all => 'Test needs ' . DBIx::Class::Optional::Dependencies->req_missing_for ('rdbms_oracle')
  unless DBIx::Class::Optional::Dependencies->req_ok_for ('rdbms_oracle');

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

use DBICTest::Schema;

my $schema = DBICTest::Schema->connect($dsn, $user, $pass);

note "Oracle Version: " . $schema->storage->_server_info->{dbms_version};

my $dbh = $schema->storage->dbh;
do_creates($dbh);

### test hierarchical queries
{
  $schema->resultset('Artist')->create ({
    name => 'root',
    rank => 1,
    cds => [],
    children => [
      {
        name => 'child1',
        rank => 2,
        children => [
          {
            name => 'grandchild',
            rank => 3,
            cds => [
              {
                title => "grandchilds's cd" ,
                year => '2008',
                tracks => [
                  {
                    position => 1,
                    title => 'Track 1 grandchild',
                  }
                ],
              }
            ],
            children => [
              {
                name => 'greatgrandchild',
                rank => 3,
              }
            ],
          }
        ],
      },
      {
        name => 'child2',
        rank => 3,
      },
    ],
  });

  $schema->resultset('Artist')->create({
    name => 'cycle-root',
    children => [
      {
        name => 'cycle-child1',
        children => [ { name => 'cycle-grandchild' } ],
      },
      {
        name => 'cycle-child2'
      },
    ],
  });

  $schema->resultset('Artist')->find({ name => 'cycle-root' })
    ->update({ parentid => { -ident => 'artistid' } });

  # select the whole tree
  {
    my $rs = $schema->resultset('Artist')->search({}, {
      start_with => { name => 'root' },
      connect_by => { parentid => { -prior => { -ident => 'artistid' } } },
    });

    is_same_sql_bind (
      $rs->as_query,
      '(
        SELECT me.artistid, me.name, me.rank, me.charfield, me.parentid
          FROM artist me
        START WITH name = ?
        CONNECT BY parentid = PRIOR artistid
      )',
      [ [ { 'sqlt_datatype' => 'varchar', 'dbic_colname' => 'name', 'sqlt_size' => 100 }
            => 'root'] ],
    );
    is_deeply (
      [ $rs->get_column ('name')->all ],
      [ qw/root child1 grandchild greatgrandchild child2/ ],
      'got artist tree',
    );

    is_same_sql_bind (
      $rs->count_rs->as_query,
      '(
        SELECT COUNT( * )
          FROM artist me
        START WITH name = ?
        CONNECT BY parentid = PRIOR artistid
      )',
      [ [ { 'sqlt_datatype' => 'varchar', 'dbic_colname' => 'name', 'sqlt_size' => 100 }
            => 'root'] ],
    );

    is( $rs->count, 5, 'Connect By count ok' );
  }

  # use order siblings by statement
  SKIP: {
    # http://download.oracle.com/docs/cd/A87860_01/doc/server.817/a85397/state21b.htm#2066123
    skip q{Oracle8i doesn't support ORDER SIBLINGS BY}, 1
      if $schema->storage->_server_info->{normalized_dbms_version} < 9;

    my $rs = $schema->resultset('Artist')->search({}, {
      start_with => { name => 'root' },
      connect_by => { parentid => { -prior => { -ident =>  'artistid' } } },
      order_siblings_by => { -desc => 'name' },
    });

    is_same_sql_bind (
      $rs->as_query,
      '(
        SELECT me.artistid, me.name, me.rank, me.charfield, me.parentid
          FROM artist me
        START WITH name = ?
        CONNECT BY parentid = PRIOR artistid
        ORDER SIBLINGS BY name DESC
      )',
      [ [ { 'sqlt_datatype' => 'varchar', 'dbic_colname' => 'name', 'sqlt_size' => 100 }
            => 'root'] ],
    );

    is_deeply (
      [ $rs->get_column ('name')->all ],
      [ qw/root child2 child1 grandchild greatgrandchild/ ],
      'Order Siblings By ok',
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
      '(
        SELECT me.artistid, me.name, me.rank, me.charfield, me.parentid
          FROM artist me
        WHERE ( parentid IS NULL )
        START WITH name = ?
        CONNECT BY parentid = PRIOR artistid
      )',
      [ [ { 'sqlt_datatype' => 'varchar', 'dbic_colname' => 'name', 'sqlt_size' => 100 }
            => 'root'] ],
    );

    is_deeply(
      [ $rs->get_column('name')->all ],
      [ 'root' ],
      'found root node',
    );
  }

  # combine a connect by with a join
  SKIP: {
    # http://download.oracle.com/docs/cd/A87860_01/doc/server.817/a85397/state21b.htm#2066123
    skip q{Oracle8i doesn't support connect by with join}, 1
      if $schema->storage->_server_info->{normalized_dbms_version} < 9;

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
      '(
        SELECT me.artistid, me.name, me.rank, me.charfield, me.parentid
          FROM artist me
          LEFT JOIN cd cds ON cds.artist = me.artistid
        WHERE ( cds.title LIKE ? )
        START WITH me.name = ?
        CONNECT BY parentid = PRIOR artistid
      )',
      [
        [ { 'sqlt_datatype' => 'varchar', 'dbic_colname' => 'cds.title', 'sqlt_size' => 100 }
            => '%cd'],
        [ { 'sqlt_datatype' => 'varchar', 'dbic_colname' => 'me.name', 'sqlt_size' => 100 }
            => 'root'],
      ],
    );

    is_deeply(
      [ $rs->get_column('name')->all ],
      [ 'grandchild' ],
      'Connect By with a join result name ok'
    );

    is_same_sql_bind (
      $rs->count_rs->as_query,
      '(
        SELECT COUNT( * )
          FROM artist me
          LEFT JOIN cd cds ON cds.artist = me.artistid
        WHERE ( cds.title LIKE ? )
        START WITH me.name = ?
        CONNECT BY parentid = PRIOR artistid
      )',
      [
        [ { 'sqlt_datatype' => 'varchar', 'dbic_colname' => 'cds.title', 'sqlt_size' => 100 }
            => '%cd'],
        [ { 'sqlt_datatype' => 'varchar', 'dbic_colname' => 'me.name', 'sqlt_size' => 100 }
            => 'root'],
      ],
    );

    is( $rs->count, 1, 'Connect By with a join; count ok' );
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
      '(
        SELECT me.artistid, me.name, me.rank, me.charfield, me.parentid
          FROM artist me
        START WITH name = ?
        CONNECT BY parentid = PRIOR artistid
        ORDER BY LEVEL ASC, name ASC
      )',
      [
        [ { 'sqlt_datatype' => 'varchar', 'dbic_colname' => 'name', 'sqlt_size' => 100 }
            => 'root'],
      ],
    );


    # Don't use "$rs->get_column ('name')->all" they build a query arround the $rs.
    #   If $rs has a order by, the order by is in the subquery and this doesn't work with Oracle 8i.
    # TODO: write extra test and fix order by handling on Oracle 8i
    is_deeply (
      [ map { $_->[1] } $rs->cursor->all ],
      [ qw/root child1 child2 grandchild greatgrandchild/ ],
      'Connect By with a order_by - result name ok (without get_column)'
    );

    SKIP: {
      skip q{Connect By with a order_by - result name ok (with get_column), Oracle8i doesn't support order by in a subquery},1
        if $schema->storage->_server_info->{normalized_dbms_version} < 9;
      is_deeply (
        [  $rs->get_column ('name')->all ],
        [ qw/root child1 child2 grandchild greatgrandchild/ ],
        'Connect By with a order_by - result name ok (with get_column)'
      );
    }
  }


  # limit a connect by
  SKIP: {
    skip q{Oracle8i doesn't support order by in a subquery}, 1
      if $schema->storage->_server_info->{normalized_dbms_version} < 9;

    my $rs = $schema->resultset('Artist')->search({}, {
      start_with => { name => 'root' },
      connect_by => { parentid => { -prior => { -ident => 'artistid' } } },
      order_by => [ { -asc => 'name' }, {  -desc => 'artistid' } ],
      rows => 2,
    });

    is_same_sql_bind (
      $rs->as_query,
      '(
        SELECT artistid, name, rank, charfield, parentid
          FROM (
            SELECT me.artistid, me.name, me.rank, me.charfield, me.parentid
              FROM artist me
            START WITH name = ?
            CONNECT BY parentid = PRIOR artistid
            ORDER BY name ASC, artistid DESC
          ) me
        WHERE ROWNUM <= ?
      )',
      [
        [ { 'sqlt_datatype' => 'varchar', 'dbic_colname' => 'name', 'sqlt_size' => 100 }
            => 'root'], [ $ROWS => 2 ],
      ],
    );

    is_deeply (
      [ $rs->get_column ('name')->all ],
      [qw/child1 child2/],
      'LIMIT a Connect By query - correct names'
    );

    is_same_sql_bind (
      $rs->count_rs->as_query,
      '(
        SELECT COUNT( * )
          FROM (
            SELECT artistid
              FROM (
                SELECT artistid, ROWNUM rownum__index
                  FROM (
                    SELECT me.artistid
                      FROM artist me
                    START WITH name = ?
                    CONNECT BY parentid = PRIOR artistid
                  ) me
              ) me
            WHERE rownum__index BETWEEN ? AND ?
          ) me
      )',
      [
        [ { 'sqlt_datatype' => 'varchar', 'dbic_colname' => 'name', 'sqlt_size' => 100 }
            => 'root'],
        [ $ROWS => 1 ],
        [ $TOTAL => 2 ],
      ],
    );

    is( $rs->count, 2, 'Connect By; LIMIT count ok' );
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
      '(
        SELECT COUNT(rank) + ?
          FROM artist me
        START WITH name = ?
        CONNECT BY parentid = PRIOR artistid
        GROUP BY( rank + ? ) HAVING count(rank) < ?
      )',
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

    is_deeply (
      [ $rs->get_column ('cnt')->all ],
      [4, 4],
      'Group By a Connect By query - correct values'
    );
  }

  # select the whole cycle tree without nocylce
  {
    my $rs = $schema->resultset('Artist')->search({}, {
      start_with => { name => 'cycle-root' },
      connect_by => { parentid => { -prior => { -ident => 'artistid' } } },
    });

    # ORA-01436:  CONNECT BY loop in user data
    throws_ok { $rs->get_column ('name')->all } qr/ORA-01436/,
      "connect by initify loop detection without nocycle";
  }

  # select the whole cycle tree with nocylce
  SKIP: {
    # http://download.oracle.com/docs/cd/A87860_01/doc/server.817/a85397/expressi.htm#1023748
    skip q{Oracle8i doesn't support connect by nocycle}, 1
      if $schema->storage->_server_info->{normalized_dbms_version} < 9;

    my $rs = $schema->resultset('Artist')->search({}, {
      start_with => { name => 'cycle-root' },
      '+select'  => \ 'CONNECT_BY_ISCYCLE',
      '+as'      => [ 'connector' ],
      connect_by_nocycle => { parentid => { -prior => { -ident => 'artistid' } } },
    });

    is_same_sql_bind (
      $rs->as_query,
      '(
        SELECT me.artistid, me.name, me.rank, me.charfield, me.parentid, CONNECT_BY_ISCYCLE
          FROM artist me
        START WITH name = ?
        CONNECT BY NOCYCLE parentid = PRIOR artistid
      )',
      [
        [ { 'sqlt_datatype' => 'varchar', 'dbic_colname' => 'name', 'sqlt_size' => 100 }
            => 'cycle-root'],
      ],
    );
    is_deeply (
      [ $rs->get_column ('name')->all ],
      [ qw/cycle-root cycle-child1 cycle-grandchild cycle-child2/ ],
      'got artist tree with nocycle (name)',
    );
    is_deeply (
      [ $rs->get_column ('connector')->all ],
      [ qw/1 0 0 0/ ],
      'got artist tree with nocycle (CONNECT_BY_ISCYCLE)',
    );

    is_same_sql_bind (
      $rs->count_rs->as_query,
      '(
        SELECT COUNT( * )
          FROM artist me
        START WITH name = ?
        CONNECT BY NOCYCLE parentid = PRIOR artistid
      )',
      [
        [ { 'sqlt_datatype' => 'varchar', 'dbic_colname' => 'name', 'sqlt_size' => 100 }
            => 'cycle-root'],
      ],
    );

    is( $rs->count, 4, 'Connect By Nocycle count ok' );
  }
}

done_testing;

sub do_creates {
  my $dbh = shift;

  eval {
    $dbh->do("DROP SEQUENCE artist_autoinc_seq");
    $dbh->do("DROP SEQUENCE artist_pk_seq");
    $dbh->do("DROP SEQUENCE cd_seq");
    $dbh->do("DROP SEQUENCE track_seq");
    $dbh->do("DROP TABLE artist");
    $dbh->do("DROP TABLE track");
    $dbh->do("DROP TABLE cd");
  };

  $dbh->do("CREATE SEQUENCE artist_pk_seq START WITH 1 MAXVALUE 999999 MINVALUE 0");
  $dbh->do("CREATE SEQUENCE cd_seq START WITH 1 MAXVALUE 999999 MINVALUE 0");
  $dbh->do("CREATE SEQUENCE track_seq START WITH 1 MAXVALUE 999999 MINVALUE 0");

  $dbh->do("CREATE TABLE artist (artistid NUMBER(12), parentid NUMBER(12), name VARCHAR(255), autoinc_col NUMBER(12), rank NUMBER(38), charfield VARCHAR2(10))");
  $dbh->do("ALTER TABLE artist ADD (CONSTRAINT artist_pk PRIMARY KEY (artistid))");

  $dbh->do("CREATE TABLE cd (cdid NUMBER(12), artist NUMBER(12), title VARCHAR(255), year VARCHAR(4), genreid NUMBER(12), single_track NUMBER(12))");
  $dbh->do("ALTER TABLE cd ADD (CONSTRAINT cd_pk PRIMARY KEY (cdid))");

  $dbh->do("CREATE TABLE track (trackid NUMBER(12), cd NUMBER(12) REFERENCES cd(cdid) DEFERRABLE, position NUMBER(12), title VARCHAR(255), last_updated_on DATE, last_updated_at DATE, small_dt DATE)");
  $dbh->do("ALTER TABLE track ADD (CONSTRAINT track_pk PRIMARY KEY (trackid))");

  $dbh->do(qq{
    CREATE OR REPLACE TRIGGER artist_insert_trg_pk
    BEFORE INSERT ON artist
    FOR EACH ROW
      BEGIN
        IF :new.artistid IS NULL THEN
          SELECT artist_pk_seq.nextval
          INTO :new.artistid
          FROM DUAL;
        END IF;
      END;
  });
  $dbh->do(qq{
    CREATE OR REPLACE TRIGGER cd_insert_trg
    BEFORE INSERT OR UPDATE ON cd
    FOR EACH ROW

      DECLARE
      tmpVar NUMBER;

      BEGIN
        tmpVar := 0;

        IF :new.cdid IS NULL THEN
          SELECT cd_seq.nextval
          INTO tmpVar
          FROM dual;

          :new.cdid := tmpVar;
        END IF;
      END;
  });
  $dbh->do(qq{
    CREATE OR REPLACE TRIGGER track_insert_trg
    BEFORE INSERT ON track
    FOR EACH ROW
      BEGIN
        IF :new.trackid IS NULL THEN
          SELECT track_seq.nextval
          INTO :new.trackid
          FROM DUAL;
        END IF;
      END;
  });
}

# clean up our mess
END {
  eval {
    my $dbh = $schema->storage->dbh;
    $dbh->do("DROP SEQUENCE artist_pk_seq");
    $dbh->do("DROP SEQUENCE cd_seq");
    $dbh->do("DROP SEQUENCE track_seq");
    $dbh->do("DROP TABLE artist");
    $dbh->do("DROP TABLE track");
    $dbh->do("DROP TABLE cd");
  };
}
