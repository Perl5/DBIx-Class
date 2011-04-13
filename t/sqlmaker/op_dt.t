use strict;
use warnings;

use Test::More;
use Test::Exception;

use lib qw(t/lib);
use DBICTest::RunMode;
use DBIC::SqlMakerTest;
use DateTime;
use DBIx::Class::SQLMaker::MSSQL;
use Try::Tiny;
use Data::Dumper::Concise;

use DBICTest;

sub unknown_col { +{ dbic_colname => '' } }

my %dbs_to_test = (
   sqlite   => 1,
   mssql    => 0,
   postgres => 0,
   oracle   => 0,
);

my %schema = (
   sqlite => DBICTest->init_schema( no_populate => 1 ),
   mssql => do {
      my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_MSSQL_ODBC_${_}" } qw/DSN USER PASS/};
      if ($dsn && $user) {
         my $s = DBICTest::Schema->connect($dsn, $user, $pass);
         try { $s->storage->ensure_connected };

         $s->storage->dbh_do (sub {
             my ($storage, $dbh) = @_;
             eval { $dbh->do("DROP TABLE event") };
             $dbh->do(<<'SQL');
CREATE TABLE event (
   id INT IDENTITY NOT NULL,
   starts_at DATE NOT NULL,
   created_on DATETIME NOT NULL,
   varchar_date VARCHAR(20),
   varchar_datetime VARCHAR(20),
   skip_inflation DATETIME,
   ts_without_tz DATETIME,

   primary key(id)
)
SQL
        $dbs_to_test{mssql} = 1;
});
$s;
      } else {
         DBICTest->init_schema( no_deploy=> 1, storage_type => '::DBI::MSSQL' )
      }
   },
   mysql => do {
      my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_MYSQL_${_}" } qw/DSN USER PASS/};
      if ($dsn && $user) {
         my $s = DBICTest::Schema->connect($dsn, $user, $pass);
         try { $s->storage->ensure_connected };

         $s->storage->dbh_do (sub {
             my ($storage, $dbh) = @_;
             eval { $dbh->do("DROP TABLE event") };
             $dbh->do(<<'SQL');
CREATE TABLE event (
   id INT AUTO_INCREMENT NOT NULL,
   starts_at DATE NOT NULL,
   created_on DATETIME NOT NULL,
   varchar_date VARCHAR(20),
   varchar_datetime VARCHAR(20),
   skip_inflation DATETIME,
   ts_without_tz DATETIME,

   primary key(id)
)
SQL
        $dbs_to_test{mysql} = 1;
});
$s;
      } else {
         DBICTest->init_schema( no_deploy=> 1, storage_type => '::DBI::mysql' )
      }
   },
   ## copypasta'd for great justice
   postgres =>  do {
      my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_PG_${_}" } qw/DSN USER PASS/};
      if ($dsn && $user) {
         my $s = DBICTest::Schema->connect($dsn, $user, $pass);
         try { $s->storage->ensure_connected };

         $s->storage->dbh_do (sub {
             my ($storage, $dbh) = @_;
             eval { $dbh->do("DROP TABLE event") };
             $dbh->do(<<'SQL');
CREATE TABLE event (
   id SERIAL NOT NULL PRIMARY KEY,
   starts_at DATE NOT NULL,
   created_on TIMESTAMP NOT NULL,
   varchar_date VARCHAR(20),
   varchar_datetime VARCHAR(20),
   skip_inflation TIMESTAMP,
   ts_without_tz TIMESTAMP WITHOUT TIME ZONE
)
SQL
        $dbs_to_test{postgres} = 1;
});
$s;
      } else {
         DBICTest->init_schema( no_deploy=> 1, storage_type => '::DBI::Pg' )
      }
   },
   oracle =>  do {
      my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_ORA_${_}" } qw/DSN USER PASS/};
      if ($dsn && $user) {
         my $s = DBICTest::Schema->connect($dsn, $user, $pass, { on_connect_call => 'datetime_setup' });
         try { $s->storage->ensure_connected };

         $s->storage->dbh_do (sub {
             my ($storage, $dbh) = @_;
             eval { $dbh->do("DROP TRIGGER trq_event_id") };
             eval { $dbh->do("DROP SEQUENCE sq_event_id") };
             eval { $dbh->do("DROP TABLE event") };
             $dbh->do('CREATE SEQUENCE sq_event_id');
             $dbh->do(<<'SQL');
CREATE TABLE event (
   id NUMBER NOT NULL,
   starts_at DATE NOT NULL,
   created_on TIMESTAMP NOT NULL,
   varchar_date VARCHAR(20),
   varchar_datetime VARCHAR(20),
   skip_inflation TIMESTAMP,
   ts_without_tz TIMESTAMP,
   CONSTRAINT PK_EVENT PRIMARY KEY (id)
)
SQL
             $dbh->do(<<'SQL');
CREATE TRIGGER trg_event_id
BEFORE INSERT ON event
FOR EACH ROW WHEN (
  new.id IS NULL OR new.id = 0
)
BEGIN
  SELECT sq_event_id.nextval
  INTO :new.id
  FROM dual;
  END;
SQL
        $dbs_to_test{oracle} = 1;
});
$s;
      } else {
         DBICTest->init_schema( no_deploy=> 1, storage_type => '::DBI::Oracle::Generic', on_connect_call => 'datetime_setup' )
      }
   },
);

my %rs = map { $_ => $schema{$_}->resultset('Event') } keys %schema;

for (grep { $schema{$_}->storage->connected } keys %rs) {
   $rs{$_}->populate([
     [qw(starts_at created_on skip_inflation)],
     ['2010-12-12', '2010-12-14 12:12:12', '2019-12-12 12:12:12'],
     ['2010-12-12', '2011-12-14 12:12:12', '2011-12-12 12:12:12'],
   ])
}

my $date = DateTime->new(
   year => 2010,
   month => 12,
   day   => 14,
   hour  => 12,
   minute => 12,
   second => 12,
);

sub hri_thing {
   return {
      starts_at => $_[0],
      created_on => $_[1],
      skip_inflation => $_[2]
   }
}

my $date2 = $date->clone->set_day(16);

my $date3 = DateTime->new(
   year => 2011,
   month => 12,
   day   => 14,
   hour  => 12,
   minute => 12,
   second => 12,
);

my $date4 = DateTime->new(
   year => 2010,
   month => 12,
   day   => 12,
);

## test format:
##   search => { dbic_search_code/params }
##   rdbms_name => literal_sql
my @tests = (

  {
    msg => '-dt_now works',
    search => { 'me.created_on' => { -dt => $date } },
    select_sql => 'me.starts_at, me.created_on, me.skip_inflation',
    where  => 'me.created_on = ?',
    bind   => [[{ dbic_colname => 'me.created_on', sqlt_datatype => 'timestamp' }, '2010-12-14 12:12:12' ]],
    hri    => [hri_thing('2010-12-12', '2010-12-14 12:12:12', '2019-12-12 12:12:12')],
    sqlite => { },
    mssql => {
      bind   => [[{ dbic_colname => 'me.created_on', sqlt_datatype => 'timestamp' }, '2010-12-14 12:12:12.000' ]],
      hri    => [hri_thing('2010-12-12', '2010-12-14 12:12:12.000', '2019-12-12 12:12:12.000')],
    },
    mysql => { },
    postgres => { },
    oracle => {
      hri    => [hri_thing('2010-12-12 00:00:00', '2010-12-14 12:12:12.000000', '2019-12-12 12:12:12.000000')],
    },
  },

  {
    msg    => '-dt_year works',
    search => { 'me.id' => 1 },
    select => [ [ -dt_year => { -ident => 'me.created_on' } ] ],
    as     => [ 'year' ],
    where  => "me.id = ?",
    bind   => [[{ dbic_colname => 'me.id', sqlt_datatype => 'integer' } => 1 ]],
    hri    => [{ year => 2010 }],
    mssql => {
      select => "DATEPART(year, me.created_on)",
    },
    mysql => {
      select => "EXTRACT(YEAR FROM me.created_on)",
    },
    sqlite => {
      select => "STRFTIME('%Y', me.created_on)",
    },
    postgres => {
      select => "date_part('year', me.created_on)",
    },
    oracle => {
      select => "EXTRACT(year FROM me.created_on)",
    },
  },

  {
    msg    => '-dt_year works with DateTime obj',
    search => { 'me.id' => 1 },
    select => [ [ -dt_year => $date ] ],
    as     => [ 'year' ],
    where  => "me.id = ?",
    hri    => [{ year => 2010 }],
    bind   => [[{ sqlt_datatype => 'timestamp' } => '2010-12-14 12:12:12' ], [{ dbic_colname => 'me.id', sqlt_datatype => 'integer' } => 1 ]],
    mssql => {
      select => "DATEPART(year, ?)",
      bind   => [[{ sqlt_datatype => 'timestamp' } => '2010-12-14 12:12:12.000' ], [{ dbic_colname => 'me.id', sqlt_datatype => 'integer' } => 1 ]],
    },
    mysql => {
      select => "EXTRACT(YEAR FROM ?)",
    },
    sqlite => {
      select => "STRFTIME('%Y', ?)",
    },
    postgres => {
      select => "date_part('year', ?)",
    },
    oracle => {
      select => "EXTRACT(year FROM TO_TIMESTAMP(?))",
    },
  },

  {
    msg    => '-dt_get (year, month) works',
    search => { 'me.id' => 1 },
    select => [ [ -dt_get => [[qw(year month)], { -ident => 'me.created_on' }] ] ],
    as     => [ qw(year month) ],
    where  => "me.id = ?",
    bind   => [[{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 1 ]],
    hri    => [{ year => 2010, month => 12 }],
    mssql => {
      select => "DATEPART(year, me.created_on), DATEPART(month, me.created_on)",
    },
    mysql => {
      select => "EXTRACT(YEAR FROM me.created_on), EXTRACT(MONTH FROM me.created_on)",
    },
    sqlite => {
      select => "STRFTIME('%Y', me.created_on), STRFTIME('%m', me.created_on)",
    },
    postgres => {
      select => "date_part('year', me.created_on), date_part('month', me.created_on)",
    },
    oracle => {
      select => "EXTRACT(year FROM me.created_on), EXTRACT(month FROM me.created_on)",
    },
  },

{
    msg    => '-dt_get (year, month) works with DateTime obj',
    search => { 'me.id' => 1 },
    select => [ [ -dt_get => [[qw(year month)], $date ] ] ],
    as     => [ qw(year month) ],
    where  => "me.id = ?",
    bind   => [
      [{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12' ],
      [{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12' ],
      [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 1 ]
    ],
    hri    => [{ year => 2010, month => 12 }],
    mssql => {
      select => "DATEPART(year, ?), DATEPART(month, ?)",
       bind   => [
         [{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12.000' ],
         [{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12.000' ],
         [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 1 ]
       ],
    },
    mysql => {
      select => "EXTRACT(YEAR FROM ?), EXTRACT(MONTH FROM ?)",
    },
    sqlite => {
      select => "STRFTIME('%Y', ?), STRFTIME('%m', ?)",
    },
    postgres => {
      select => "date_part('year', ?), date_part('month', ?)",
    },
    oracle => {
      select => "EXTRACT(year FROM TO_TIMESTAMP(?)), EXTRACT(month FROM TO_TIMESTAMP(?))",
    },
  },

  {
    msg    => '-dt_month works',
    search => { 'me.id' => 1 },
    select => [ [ -dt_month => { -ident => 'me.created_on' } ] ],
    as     => [ 'month' ],
    where  => "me.id = ?",
    bind   => [[{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 1 ]],
    hri    => [{ month => 12 }],
    sqlite => {
      select   => "STRFTIME('%m', me.created_on)",
    },
    mssql => {
      select => "DATEPART(month, me.created_on)",
    },
    mysql => {
      select => "EXTRACT(MONTH FROM me.created_on)",
    },
    postgres => {
      select => "date_part('month', me.created_on)",
    },
    oracle => {
      select => "EXTRACT(month FROM me.created_on)",
    },
  },

  {
    msg    => '-dt_month works with DateTime obj',
    search => { 'me.id' => 1 },
    select => [ [ -dt_month => $date ] ],
    as     => [ 'month' ],
    where  => "me.id = ?",
    bind   => [[{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12' ], [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 1 ]],
    hri    => [{ month => 12 }],
    sqlite => {
      select   => "STRFTIME('%m', ?)",
    },
    mssql => {
      bind   => [[{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12.000' ], [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 1 ]],
      select => "DATEPART(month, ?)",
    },
    mysql => {
      select => "EXTRACT(MONTH FROM ?)",
    },
    postgres => {
      select => "date_part('month', ?)",
    },
    oracle => {
      select => "EXTRACT(month FROM TO_TIMESTAMP(?))",
    },
  },

  {
    msg    => '-dt_day works',
    search => { 'me.id' => 1 },
    select => [ [ -dt_day => { -ident => 'me.created_on' } ] ],
    as     => [ 'day' ],
    where  => "me.id = ?",
    bind   => [[{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 1 ]],
    hri    => [{ day => 14 }],
    sqlite => {
      select   => "STRFTIME('%d', me.created_on)",
    },
    mssql => {
      select => "DATEPART(day, me.created_on)",
    },
    mysql => {
      select => "EXTRACT(DAY FROM me.created_on)",
    },
    postgres => {
      select => "date_part('day', me.created_on)",
    },
    oracle => {
      select => "EXTRACT(day FROM me.created_on)",
    },
  },

  {
    msg    => '-dt_day works with DateTime obj',
    search => { 'me.id' => 1 },
    select => [ [ -dt_day => $date ] ],
    as     => [ 'day' ],
    where  => "me.id = ?",
    bind   => [[{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12' ], [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 1 ]],
    hri    => [{ day => 14 }],
    sqlite => {
      select   => "STRFTIME('%d', ?)",
    },
    mssql => {
      select => "DATEPART(day, ?)",
      bind   => [[{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12.000' ], [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 1 ]],
    },
    mysql => {
      select => "EXTRACT(DAY FROM ?)",
    },
    postgres => {
      select => "date_part('day', ?)",
    },
    oracle => {
      select => "EXTRACT(day FROM TO_TIMESTAMP(?))",
    },
  },

  {
    msg    => '-dt_hour works',
    search => { 'me.id' => 1 },
    select => [ [ -dt_hour => { -ident => 'me.created_on' } ] ],
    as     => [ 'hour' ],
    where  => "me.id = ?",
    bind   => [[{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 1 ]],
    hri    => [{ hour => 12 }],
    sqlite => {
      select   => "STRFTIME('%H', me.created_on)",
    },
    mssql => {
      select => "DATEPART(hour, me.created_on)",
    },
    mysql => {
      select => "EXTRACT(HOUR FROM me.created_on)",
    },
    postgres => {
      select => "date_part('hour', me.created_on)",
    },
    oracle => {
      select => "EXTRACT(hour FROM me.created_on)",
    },
  },

  {
    msg    => '-dt_hour works with DateTime obj',
    search => { 'me.id' => 1 },
    select => [ [ -dt_hour => $date ] ],
    as     => [ 'hour' ],
    where  => "me.id = ?",
    bind   => [[{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12' ], [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 1 ]],
    hri    => [{ hour => 12 }],
    sqlite => {
      select   => "STRFTIME('%H', ?)",
    },
    mssql => {
      select => "DATEPART(hour, ?)",
      bind   => [[{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12.000' ], [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 1 ]],
    },
    mysql => {
      select => "EXTRACT(HOUR FROM ?)",
    },
    postgres => {
      select => "date_part('hour', ?)",
    },
    oracle => {
      select => "EXTRACT(hour FROM TO_TIMESTAMP(?))",
    },
  },

  {
    msg    => '-dt_minute works',
    search => { 'me.id' => 1 },
    select => [ [ -dt_minute => { -ident => 'me.created_on' } ] ],
    as     => [ 'minute' ],
    where  => "me.id = ?",
    bind   => [[{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 1 ]],
    hri    => [{ minute => 12 }],
    sqlite => {
      select   => "STRFTIME('%M', me.created_on)",
    },
    mssql => {
      select => "DATEPART(minute, me.created_on)",
    },
    mysql => {
      select => "EXTRACT(MINUTE FROM me.created_on)",
    },
    postgres => {
      select => "date_part('minute', me.created_on)",
    },
    oracle => {
      select => "EXTRACT(minute FROM me.created_on)",
    },
  },

  {
    msg    => '-dt_minute works with DateTime obj',
    search => { 'me.id' => 1 },
    select => [ [ -dt_minute => $date ] ],
    as     => [ 'minute' ],
    where  => "me.id = ?",
    bind   => [[{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12' ], [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 1 ]],
    hri    => [{ minute => 12 }],
    sqlite => {
      select   => "STRFTIME('%M', ?)",
    },
    mssql => {
      select => "DATEPART(minute, ?)",
      bind   => [[{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12.000' ], [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 1 ]],
    },
    mysql => {
      select => "EXTRACT(MINUTE FROM ?)",
    },
    postgres => {
      select => "date_part('minute', ?)",
    },
    oracle => {
      select => "EXTRACT(minute FROM TO_TIMESTAMP(?))",
    },
  },

  {
    msg    => '-dt_second works',
    search => { 'me.id' => 1 },
    select => [ [ -dt_second => { -ident => 'me.created_on' } ] ],
    as     => [ 'second' ],
    where  => "me.id = ?",
    bind   => [[{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 1 ]],
    hri    => [{ second => 12 }],
    sqlite => {
      select   => "STRFTIME('%S', me.created_on)",
    },
    mssql => {
      select => "DATEPART(second, me.created_on)",
    },
    mysql => {
      select => "EXTRACT(SECOND FROM me.created_on)",
    },
    postgres => {
      select => "date_part('second', me.created_on)",
    },
    oracle => {
      select => "EXTRACT(second FROM me.created_on)",
    },
  },

  {
    msg    => '-dt_second works with DateTime obj',
    search => { 'me.id' => 1 },
    select => [ [ -dt_second => $date ] ],
    as     => [ 'second' ],
    where  => "me.id = ?",
    bind   => [[{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12' ], [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 1 ]],
    hri    => [{ second => 12 }],
    sqlite => {
      select   => "STRFTIME('%S', ?)",
    },
    mssql => {
      select => "DATEPART(second, ?)",
      bind   => [[{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12.000' ], [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 1 ]],
    },
    mysql => {
      select => "EXTRACT(SECOND FROM ?)",
    },
    postgres => {
      select => "date_part('second', ?)",
    },
    oracle => {
      select => "EXTRACT(second FROM TO_TIMESTAMP(?))",
    },
  },

  {
    msg    => '-dt_diff (second) works',
    search => { 'me.id' => 2 },
    select => [ [ -dt_diff => [second => { -ident => 'me.created_on' }, \'me.skip_inflation' ] ] ],
    as     => [ 'sec_diff' ],
    where  => "me.id = ?",
    bind   => [[{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]],
    hri    => [{ sec_diff => 2*24*60*60 }],
    sqlite => {
      select   => "(STRFTIME('%s', me.created_on) - STRFTIME('%s', me.skip_inflation))",
    },
    mssql => {
      select   => "DATEDIFF(second, me.skip_inflation, me.created_on)",
    },
    mysql => {
      select   => "TIMESTAMPDIFF(SECOND, me.skip_inflation, me.created_on)",
    },
    postgres => {
      select   => "date_part('EPOCH', me.created_on) - date_part('EPOCH', me.skip_inflation)",
    },
    oracle => {
      select   => "TRUNC(MONTHS_BETWEEN(me.created_on, me.skip_inflation) * 31 * 24 * 60 * 60)",
    },
  },

  {
    msg    => '-dt_diff (second) works with DateTime objs',
    search => { 'me.id' => 2 },
    select => [ [ -dt_diff => [second => $date2, $date ] ] ],
    as     => [ 'sec_diff' ],
    where  => "me.id = ?",
    bind   => [
      [{sqlt_datatype => 'timestamp'} => '2010-12-16 12:12:12' ],
      [{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12' ],
      [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]
    ],
    hri    => [{ sec_diff => 2*24*60*60 }],
    sqlite => {
      select   => "(STRFTIME('%s', ?) - STRFTIME('%s', ?))",
    },
    mssql => {
      select   => "DATEDIFF(second, ?, ?)",
      bind   => [
        [{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12.000' ],
        [{sqlt_datatype => 'timestamp'} => '2010-12-16 12:12:12.000' ],
        [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]
      ],
    },
    mysql => {
      select   => "TIMESTAMPDIFF(SECOND, ?, ?)",
      bind   => [
        [{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12' ],
        [{sqlt_datatype => 'timestamp'} => '2010-12-16 12:12:12' ],
        [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]
      ],
    },
    postgres => {
      select   => "date_part('EPOCH', ?) - date_part('EPOCH', ?)",
    },
    oracle => {
      select   => "TRUNC(MONTHS_BETWEEN(?, ?) * 31 * 24 * 60 * 60)",
    },
  },

  {
    msg    => '-dt_diff (day) works',
    search => { 'me.id' => 2 },
    select => [ [ -dt_diff => [day => { -ident => 'me.created_on' }, \'me.skip_inflation' ] ] ],
    as     => [ 'day_diff' ],
    where  => "me.id = ?",
    bind   => [[{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]],
    hri    => [{ day_diff => 2 }],
    sqlite => {
      select   => "(JULIANDAY(me.created_on) - JULIANDAY(me.skip_inflation))",
    },
    mssql => {
      select   => "DATEDIFF(dayofyear, me.skip_inflation, me.created_on)",
    },
    mysql => {
      select   => "TIMESTAMPDIFF(DAY, me.skip_inflation, me.created_on)",
    },
    postgres => {
      select   => "date_part('DAY', me.created_on) - date_part('DAY', me.skip_inflation)",
    },
    oracle => {
      select   => "TRUNC(MONTHS_BETWEEN(me.created_on, me.skip_inflation) * 31)",
    },
  },

  {
    msg    => '-dt_diff (day) works with DateTime objs',
    search => { 'me.id' => 2 },
    select => [ [ -dt_diff => [day => $date2, $date ] ] ],
    as     => [ 'day_diff' ],
    where  => "me.id = ?",
    bind   => [
      [{sqlt_datatype => 'timestamp'} => '2010-12-16 12:12:12' ],
      [{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12' ],
      [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]
    ],
    hri    => [{ day_diff => 2 }],
    sqlite => {
      select   => "(JULIANDAY(?) - JULIANDAY(?))",
    },
    mssql => {
      bind   => [
        [{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12.000' ],
        [{sqlt_datatype => 'timestamp'} => '2010-12-16 12:12:12.000' ],
        [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]
      ],
      select   => "DATEDIFF(dayofyear, ?, ?)",
    },
    mysql => {
      bind   => [
        [{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12' ],
        [{sqlt_datatype => 'timestamp'} => '2010-12-16 12:12:12' ],
        [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]
      ],
      select   => "TIMESTAMPDIFF(DAY, ?, ?)",
    },
    postgres => {
      select   => "date_part('DAY', ?) - date_part('DAY', ?)",
    },
    oracle => {
      select   => "TRUNC(MONTHS_BETWEEN(?, ?) * 31)",
    },
  },

  {
    msg    => '-dt_diff (year) works',
    search => { 'me.id' => 2 },
    select => [ [ -dt_diff => [year => \'me.starts_at', { -ident => 'me.created_on' } ] ] ],
    as     => [ 'year' ],
    where  => "me.id = ?",
    bind   => [[{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]],
    hri    => [{ year => -1 }],
    sqlite => {
      exception_like => qr/date diff not supported for part "year" with database "SQLite"/,
    },
    mssql => {
      select   => "DATEDIFF(year, me.created_on, me.starts_at)",
    },
    mysql => {
      select   => "TIMESTAMPDIFF(YEAR, me.created_on, me.starts_at)",
    },
    postgres => {
      select   => "date_part('YEAR', me.starts_at) - date_part('YEAR', me.created_on)",
    },
    oracle => {
      select   => "TRUNC(MONTHS_BETWEEN(me.starts_at, me.created_on) / 12)",
    },
  },

  {
    msg    => '-dt_diff (year) works with DateTime objs',
    search => { 'me.id' => 2 },
    select => [ [ -dt_diff => [year => $date4, $date3 ] ] ],
    as     => [ 'year' ],
    where  => "me.id = ?",
    bind   => [
      [{sqlt_datatype => 'timestamp'} => '2010-12-12 00:00:00' ],
      [{sqlt_datatype => 'timestamp'} => '2011-12-14 12:12:12' ],
      [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]
    ],
    hri    => [{ year => -1 }],
    sqlite => {
      exception_like => qr/date diff not supported for part "year" with database "SQLite"/,
    },
    mssql => {
      select   => "DATEDIFF(year, ?, ?)",
      bind   => [
        [{sqlt_datatype => 'timestamp'} => '2011-12-14 12:12:12.000' ],
        [{sqlt_datatype => 'timestamp'} => '2010-12-12 00:00:00.000' ],
        [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]
      ],
    },
    mysql => {
      select   => "TIMESTAMPDIFF(YEAR, ?, ?)",
      bind   => [
        [{sqlt_datatype => 'timestamp'} => '2011-12-14 12:12:12' ],
        [{sqlt_datatype => 'timestamp'} => '2010-12-12 00:00:00' ],
        [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]
      ],
    },
    postgres => {
      select   => "date_part('YEAR', ?) - date_part('YEAR', ?)",
    },
    oracle => {
      select   => "TRUNC(MONTHS_BETWEEN(?, ?) / 12)",
    },
  },

  {
    msg    => '-dt_add (year) works',
    search => { 'me.id' => 2 },
    select => [ [ -dt_add => [year => 3, { -ident => 'me.created_on' } ] ] ],
    as     => [ 'date' ],
    where  => "me.id = ?",
    bind   => [[unknown_col, 3], [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]],
    hri    => [{ date => '2014-12-14 12:12:12' }],
    sqlite => {
      select => "(datetime(me.created_on, ? || ' years'))",
    },
    mssql => {
      select => "(DATEADD(year, CAST(? AS INTEGER), me.created_on))",
      bind   => [[{sqlt_datatype => 'integer'}, 3], [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]],
      hri    => [{ date => '2014-12-14 12:12:12.000' }],
    },
    mysql => {
      select => "DATE_ADD(me.created_on, INTERVAL ? YEAR)",
    },
    postgres => {
      select => "(me.created_on + ? * interval '1 YEAR')",
    },
    oracle => {
      select => "(me.created_on + NUMTOYMINTERVAL(?, 'year'))",
      hri    => [{ date => '2014-12-14 12:12:12.000000000' }],
    },
  },

  {
    msg    => '-dt_add (year) works with DateTime obj',
    search => { 'me.id' => 2 },
    select => [ [ -dt_add => [year => 3, $date ] ] ],
    as     => [ 'date' ],
    where  => "me.id = ?",
    bind   => [
      [{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12' ],
      [unknown_col, 3],
      [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]
    ],
    hri    => [{ date => '2013-12-14 12:12:12' }],
    sqlite => {
      select => "(datetime(?, ? || ' years'))",
    },
    mssql => {
      select => "(DATEADD(year, CAST(? AS INTEGER), ?))",
      bind   => [
         [{sqlt_datatype => 'integer'}, 3],
         [{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12.000' ],
         [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]
      ],
      hri    => [{ date => '2013-12-14 12:12:12.000' }],
    },
    mysql => {
      select => "DATE_ADD(?, INTERVAL ? YEAR)",
    },
    postgres => {
      select => "(? + ? * interval '1 YEAR')",
    },
    oracle => {
      select => "(TO_TIMESTAMP(?) + NUMTOYMINTERVAL(?, 'year'))",
      hri    => [{ date => '2013-12-14 12:12:12.000000000' }],
    },
  },

  {
    msg    => '-dt_add (month) works',
    search => { 'me.id' => 2 },
    select => [ [ -dt_add => [month => 3, { -ident => 'me.created_on' } ] ] ],
    as     => [ 'date' ],
    where  => "me.id = ?",
    bind   => [[unknown_col, 3], [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]],
    hri    => [{ date => '2012-03-14 12:12:12' }],
    sqlite => {
      select => "(datetime(me.created_on, ? || ' months'))",
    },
    mssql => {
      select => "(DATEADD(month, CAST(? AS INTEGER), me.created_on))",
      bind   => [[{sqlt_datatype => 'integer'}, 3], [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]],
      hri    => [{ date => '2012-03-14 12:12:12.000' }],
    },
    postgres => {
      select => "(me.created_on + ? * interval '1 MONTH')",
    },
    mysql => {
      select => "DATE_ADD(me.created_on, INTERVAL ? MONTH)",
    },
    oracle => {
      select => "(me.created_on + NUMTOYMINTERVAL(?, 'month'))",
      hri    => [{ date => '2012-03-14 12:12:12.000000000' }],
    },
  },

  {
    msg    => '-dt_add (month) works with DateTime obj',
    search => { 'me.id' => 2 },
    select => [ [ -dt_add => [month => 3, $date ] ] ],
    as     => [ 'date' ],
    where  => "me.id = ?",
    bind   => [
      [{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12' ],
      [unknown_col, 3],
      [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]
    ],
    hri    => [{ date => '2011-03-14 12:12:12' }],
    sqlite => {
      select => "(datetime(?, ? || ' months'))",
    },
    mssql => {
      select => "(DATEADD(month, CAST(? AS INTEGER), ?))",
      bind   => [
         [{sqlt_datatype => 'integer'}, 3],
         [{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12.000' ],
         [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]
      ],
      hri    => [{ date => '2011-03-14 12:12:12.000' }],
    },
    postgres => {
      select => "(? + ? * interval '1 MONTH')",
    },
    mysql => {
      select => "DATE_ADD(?, INTERVAL ? MONTH)",
    },
    oracle => {
      select => "(TO_TIMESTAMP(?) + NUMTOYMINTERVAL(?, 'month'))",
      hri    => [{ date => '2011-03-14 12:12:12.000000000' }],
    },
  },

  {
    msg    => '-dt_add (day) works',
    search => { 'me.id' => 2 },
    select => [ [ -dt_add => [day => 3, { -ident => 'me.created_on' } ] ] ],
    as     => [ 'date' ],
    where  => "me.id = ?",
    bind   => [[unknown_col, 3], [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]],
    hri    => [{ date => '2011-12-17 12:12:12' }],
    sqlite => {
      select => "(datetime(me.created_on, ? || ' days'))",
    },
    mssql => {
      select => "(DATEADD(dayofyear, CAST(? AS INTEGER), me.created_on))",
      bind   => [[{sqlt_datatype => 'integer'}, 3], [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]],
      hri    => [{ date => '2011-12-17 12:12:12.000' }],
    },
    postgres => {
      select => "(me.created_on + ? * interval '1 DAY')",
    },
    mysql => {
      select => "DATE_ADD(me.created_on, INTERVAL ? DAY)",
    },
    oracle => {
      select => "(me.created_on + NUMTODSINTERVAL(?, 'day'))",
      hri    => [{ date => '2011-12-17 12:12:12.000000000' }],
    },
  },

  {
    msg    => '-dt_add (day) works with DateTime obj',
    search => { 'me.id' => 2 },
    select => [ [ -dt_add => [day => 3, $date ] ] ],
    as     => [ 'date' ],
    where  => "me.id = ?",
    bind   => [
      [{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12' ],
      [unknown_col, 3],
      [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]
    ],
    hri    => [{ date => '2010-12-17 12:12:12' }],
    sqlite => {
      select => "(datetime(?, ? || ' days'))",
    },
    mssql => {
      select => "(DATEADD(dayofyear, CAST(? AS INTEGER), ?))",
      bind   => [
         [{sqlt_datatype => 'integer'}, 3],
         [{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12.000' ],
         [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]
      ],
      hri    => [{ date => '2010-12-17 12:12:12.000' }],
    },
    postgres => {
      select => "(? + ? * interval '1 DAY')",
    },
    mysql => {
      select => "DATE_ADD(?, INTERVAL ? DAY)",
    },
    oracle => {
      select => "(TO_TIMESTAMP(?) + NUMTODSINTERVAL(?, 'day'))",
      hri    => [{ date => '2010-12-17 12:12:12.000000000' }],
    },
  },

  {
    msg    => '-dt_add (hour) works',
    search => { 'me.id' => 2 },
    select => [ [ -dt_add => [hour => 3, { -ident => 'me.created_on' } ] ] ],
    as     => [ 'date' ],
    where  => "me.id = ?",
    bind   => [[unknown_col, 3], [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]],
    hri    => [{ date => '2011-12-14 15:12:12' }],
    sqlite => {
      select => "(datetime(me.created_on, ? || ' hours'))",
    },
    mssql => {
      select => "(DATEADD(hour, CAST(? AS INTEGER), me.created_on))",
      bind   => [[{sqlt_datatype => 'integer'}, 3], [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]],
      hri    => [{ date => '2011-12-14 15:12:12.000' }],
    },
    postgres => {
      select => "(me.created_on + ? * interval '1 HOUR')",
    },
    mysql => {
      select => "DATE_ADD(me.created_on, INTERVAL ? HOUR)",
    },
    oracle => {
      select => "(me.created_on + NUMTODSINTERVAL(?, 'hour'))",
      hri    => [{ date => '2011-12-14 15:12:12.000000000' }],
    },
  },

  {
    msg    => '-dt_add (hour) works with DateTime obj',
    search => { 'me.id' => 2 },
    select => [ [ -dt_add => [hour => 3, $date ] ] ],
    as     => [ 'date' ],
    where  => "me.id = ?",
    bind   => [
      [{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12' ],
      [unknown_col, 3],
      [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]
    ],
    hri    => [{ date => '2010-12-14 15:12:12' }],
    sqlite => {
      select => "(datetime(?, ? || ' hours'))",
    },
    mssql => {
      select => "(DATEADD(hour, CAST(? AS INTEGER), ?))",
      bind   => [
         [{sqlt_datatype => 'integer'}, 3],
         [{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12.000' ],
         [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]
      ],
      hri    => [{ date => '2010-12-14 15:12:12.000' }],
    },
    postgres => {
      select => "(? + ? * interval '1 HOUR')",
    },
    mysql => {
      select => "DATE_ADD(?, INTERVAL ? HOUR)",
    },
    oracle => {
      select => "(TO_TIMESTAMP(?) + NUMTODSINTERVAL(?, 'hour'))",
      hri    => [{ date => '2010-12-14 15:12:12.000000000' }],
    },
  },

  {
    msg    => '-dt_add (minute) works',
    search => { 'me.id' => 2 },
    select => [ [ -dt_add => [minute => 3, { -ident => 'me.created_on' } ] ] ],
    as     => [ 'date' ],
    where  => "me.id = ?",
    bind   => [[unknown_col, 3], [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]],
    hri    => [{ date => '2011-12-14 12:15:12' }],
    sqlite => {
      select => "(datetime(me.created_on, ? || ' minutes'))",
    },
    mssql => {
      select => "(DATEADD(minute, CAST(? AS INTEGER), me.created_on))",
      bind   => [[{sqlt_datatype => 'integer'}, 3], [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]],
      hri    => [{ date => '2011-12-14 12:15:12.000' }],
    },
    postgres => {
      select => "(me.created_on + ? * interval '1 MINUTE')",
    },
    mysql => {
      select => "DATE_ADD(me.created_on, INTERVAL ? MINUTE)",
    },
    oracle => {
      select => "(me.created_on + NUMTODSINTERVAL(?, 'minute'))",
      hri    => [{ date => '2011-12-14 12:15:12.000000000' }],
    },
  },

  {
    msg    => '-dt_add (minute) works with DateTime obj',
    search => { 'me.id' => 2 },
    select => [ [ -dt_add => [minute => 3, $date ] ] ],
    as     => [ 'date' ],
    where  => "me.id = ?",
    bind   => [
      [{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12' ],
      [unknown_col, 3],
      [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]
    ],
    hri    => [{ date => '2010-12-14 12:15:12' }],
    sqlite => {
      select => "(datetime(?, ? || ' minutes'))",
    },
    mssql => {
      select => "(DATEADD(minute, CAST(? AS INTEGER), ?))",
      bind   => [
         [{sqlt_datatype => 'integer'}, 3],
         [{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12.000' ],
         [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]
      ],
      hri    => [{ date => '2010-12-14 12:15:12.000' }],
    },
    postgres => {
      select => "(? + ? * interval '1 MINUTE')",
    },
    mysql => {
      select => "DATE_ADD(?, INTERVAL ? MINUTE)",
    },
    oracle => {
      select => "(TO_TIMESTAMP(?) + NUMTODSINTERVAL(?, 'minute'))",
      hri    => [{ date => '2010-12-14 12:15:12.000000000' }],
    },
  },

  {
    msg    => '-dt_add (second) works',
    search => { 'me.id' => 2 },
    select => [ [ -dt_add => [second => 3, { -ident => 'me.created_on' } ] ] ],
    as     => [ 'date' ],
    where  => "me.id = ?",
    bind   => [[unknown_col, 3], [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]],
    hri    => [{ date => '2011-12-14 12:12:15' }],
    sqlite => {
      select => "(datetime(me.created_on, ? || ' seconds'))",
    },
    mssql => {
      select => "(DATEADD(second, CAST(? AS INTEGER), me.created_on))",
      bind   => [[{sqlt_datatype => 'integer'}, 3], [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]],
      hri    => [{ date => '2011-12-14 12:12:15.000' }],
    },
    postgres => {
      select => "(me.created_on + ? * interval '1 SECOND')",
    },
    mysql => {
      select => "DATE_ADD(me.created_on, INTERVAL ? SECOND)",
    },
    oracle => {
      select => "(me.created_on + NUMTODSINTERVAL(?, 'second'))",
      hri    => [{ date => '2011-12-14 12:12:15.000000000' }],
    },
  },

  {
    msg    => '-dt_add (second) works with DateTime obj',
    search => { 'me.id' => 2 },
    select => [ [ -dt_add => [second => 3, $date ] ] ],
    as     => [ 'date' ],
    where  => "me.id = ?",
    bind   => [
      [{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12' ],
      [unknown_col, 3],
      [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]
    ],
    hri    => [{ date => '2010-12-14 12:12:15' }],
    sqlite => {
      select => "(datetime(?, ? || ' seconds'))",
    },
    mssql => {
      select => "(DATEADD(second, CAST(? AS INTEGER), ?))",
      bind   => [
         [{sqlt_datatype => 'integer'}, 3],
         [{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12.000' ],
         [{dbic_colname => 'me.id', sqlt_datatype => 'integer'} => 2 ]
      ],
      hri    => [{ date => '2010-12-14 12:12:15.000' }],
    },
    postgres => {
      select => "(? + ? * interval '1 SECOND')",
    },
    mysql => {
      select => "DATE_ADD(?, INTERVAL ? SECOND)",
    },
    oracle => {
      select => "(TO_TIMESTAMP(?) + NUMTODSINTERVAL(?, 'second'))",
      hri    => [{ date => '2010-12-14 12:12:15.000000000' }],
    },
  },

  {
    msg    => 'nested -dt_add works',
    search => { 'me.id' => 2 },
    select => [ [ -dt_add => [second => 3, { -dt_add => [ day => 1, { -ident => 'me.created_on' } ] } ] ] ],
    as     => [ 'date' ],
    where  => "me.id = ?",
    hri    => [{ date => '2011-12-15 12:12:15' }],
    bind   => [[unknown_col, 1], [unknown_col, 3 ], [{dbic_colname => 'me.id', sqlt_datatype => 'integer' }, 2]],
    sqlite => {
      select   => "(datetime((datetime(me.created_on, ? || ' days')), ? || ' seconds'))",
    },
    mssql => {
      select => "(DATEADD(second, CAST(? AS INTEGER), (DATEADD(dayofyear, CAST(? AS INTEGER), me.created_on))))",
      bind   => [[{sqlt_datatype => 'integer'}, 3 ], [{sqlt_datatype => 'integer'}, 1], [{dbic_colname => 'me.id', sqlt_datatype => 'integer' }, 2]],
      hri    => [{ date => '2011-12-15 12:12:15.000' }],
    },
     postgres => {
      select => "((me.created_on + ? * interval '1 DAY') + ? * interval '1 SECOND')",
    },
    mysql => {
      select => "DATE_ADD(DATE_ADD(me.created_on, INTERVAL ? DAY), INTERVAL ? SECOND)",
    },
    oracle => {
      select => "((me.created_on + NUMTODSINTERVAL(?, 'day')) + NUMTODSINTERVAL(?, 'second'))",
      hri    => [{ date => '2011-12-15 12:12:15.000000000' }],
    },
  },

  {
    msg    => 'nested -dt_add works with DateTime obj',
    search => { 'me.id' => 2 },
    select => [ [ -dt_add => [second => 3, { -dt_add => [ day => 1, $date ] } ] ] ],
    as     => [ 'date' ],
    where  => "me.id = ?",
    hri    => [{ date => '2010-12-15 12:12:15' }],
    bind   => [
      [{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12' ],
      [unknown_col, 1],
      [unknown_col, 3 ],
      [{dbic_colname => 'me.id', sqlt_datatype => 'integer' }, 2]
    ],
    sqlite => {
      select   => "(datetime((datetime(?, ? || ' days')), ? || ' seconds'))",
    },
    mssql => {
      select => "(DATEADD(second, CAST(? AS INTEGER), (DATEADD(dayofyear, CAST(? AS INTEGER), ?))))",
    bind   => [
      [{sqlt_datatype => 'integer'}, 3 ],
      [{sqlt_datatype => 'integer'}, 1],
      [{sqlt_datatype => 'timestamp'} => '2010-12-14 12:12:12.000' ],
      [{dbic_colname => 'me.id', sqlt_datatype => 'integer' }, 2]
    ],
      hri    => [{ date => '2010-12-15 12:12:15.000' }],
    },
     postgres => {
      select => "((? + ? * interval '1 DAY') + ? * interval '1 SECOND')",
    },
    mysql => {
      select => "DATE_ADD(DATE_ADD(?, INTERVAL ? DAY), INTERVAL ? SECOND)",
    },
    oracle => {
      select => "((TO_TIMESTAMP(?) + NUMTODSINTERVAL(?, 'day')) + NUMTODSINTERVAL(?, 'second'))",
      hri    => [{ date => '2010-12-15 12:12:15.000000000' }],
    },
  },

  {
    msg      => '-dt_before works',
    search   => { 'me.created_on' => { -dt_before => '2011-12-14 12:12:12' } },
    select   => [ [ -ident => 'me.created_on' ] ],
    as       => [ 'date' ],
    select_sql   => "me.created_on",
    where    => "me.created_on < ?",
    bind     => [[{dbic_colname => 'me.created_on', sqlt_datatype => 'timestamp' }, '2011-12-14 12:12:12']],
    hri      => [{ date => '2010-12-14 12:12:12' }],
    sqlite   => { },
    postgres => { },
    mysql    => { },
    mssql    => {
      hri => [{ date => '2010-12-14 12:12:12.000' }],
    },
    oracle   => {
      hri => [{ date => '2010-12-14 12:12:12.000000' }],
    },
  },

  {
    msg      => '-dt_before works with DateTime obj',
    search   => { 'me.created_on' => { -dt_before => $date3 } },
    select   => [ [ -ident => 'me.created_on' ] ],
    as       => [ 'date' ],
    select_sql   => "me.created_on",
    where    => "me.created_on < ?",
    bind     => [[{sqlt_datatype => 'timestamp' }, '2011-12-14 12:12:12']],
    hri      => [{ date => '2010-12-14 12:12:12' }],
    sqlite   => { },
    postgres => { },
    mysql    => { },
    mssql    => {
      hri => [{ date => '2010-12-14 12:12:12.000' }],
      bind => [[{sqlt_datatype => 'timestamp' }, '2011-12-14 12:12:12.000']],
    },
    oracle   => {
      hri => [{ date => '2010-12-14 12:12:12.000000' }],
    },
  },

  {
    msg      => '-dt_on_or_before works',
    search   => { 'me.created_on' => { -dt_on_or_before => '2011-12-14 12:12:12' } },
    select   => [ [ -ident => 'me.created_on' ] ],
    as       => [ 'date' ],
    select_sql   => "me.created_on",
    where    => "me.created_on <= ?",
    bind     => [[{dbic_colname => 'me.created_on', sqlt_datatype => 'timestamp' }, '2011-12-14 12:12:12']],
    hri      => [{ date => '2010-12-14 12:12:12' }, { date => '2011-12-14 12:12:12' }],
    sqlite   => { },
    postgres => { },
    mysql    => { },
    mssql    => {
      hri => [{ date => '2010-12-14 12:12:12.000' }, { date => '2011-12-14 12:12:12.000' }],
    },
    oracle   => {
      hri => [{ date => '2010-12-14 12:12:12.000000' }, { date => '2011-12-14 12:12:12.000000' }],
    },
  },

  {
    msg      => '-dt_on_or_before works with DateTime obj',
    search   => { 'me.created_on' => { -dt_on_or_before => $date3 } },
    select   => [ [ -ident => 'me.created_on' ] ],
    as       => [ 'date' ],
    select_sql   => "me.created_on",
    where    => "me.created_on <= ?",
    bind     => [[{sqlt_datatype => 'timestamp' }, '2011-12-14 12:12:12']],
    hri      => [{ date => '2010-12-14 12:12:12' }, { date => '2011-12-14 12:12:12' }],
    sqlite   => { },
    postgres => { },
    mysql    => { },
    mssql    => {
      hri => [{ date => '2010-12-14 12:12:12.000' }, { date => '2011-12-14 12:12:12.000' }],
      bind => [[{sqlt_datatype => 'timestamp' }, '2011-12-14 12:12:12.000']],
    },
    oracle   => {
      hri => [{ date => '2010-12-14 12:12:12.000000' }, { date => '2011-12-14 12:12:12.000000' }],
    },
  },

  {
    msg      => '-dt_after works',
    search   => { 'me.created_on' => { -dt_after => '2010-12-14 12:12:12' } },
    select   => [ [ -ident => 'me.created_on' ] ],
    as       => [ 'date' ],
    select_sql => "me.created_on",
    where    => "me.created_on > ?",
    bind     => [[{dbic_colname => 'me.created_on', sqlt_datatype => 'timestamp' }, '2010-12-14 12:12:12']],
    hri      => [{ date => '2011-12-14 12:12:12' }],
    sqlite   => { },
    postgres => { },
    mysql    => { },
    mssql    => {
      hri => [{ date => '2011-12-14 12:12:12.000' }],
    },
    oracle   => {
      hri => [{ date => '2011-12-14 12:12:12.000000' }],
    },
  },

  {
    msg      => '-dt_after works with DateTime obj',
    search   => { 'me.created_on' => { -dt_after => $date } },
    select   => [ [ -ident => 'me.created_on' ] ],
    as       => [ 'date' ],
    select_sql => "me.created_on",
    where    => "me.created_on > ?",
    bind     => [[{sqlt_datatype => 'timestamp' }, '2010-12-14 12:12:12']],
    hri      => [{ date => '2011-12-14 12:12:12' }],
    sqlite   => { },
    postgres => { },
    mysql    => { },
    mssql    => {
      hri => [{ date => '2011-12-14 12:12:12.000' }],
      bind     => [[{sqlt_datatype => 'timestamp' }, '2010-12-14 12:12:12.000']],
    },
    oracle   => {
      hri => [{ date => '2011-12-14 12:12:12.000000' }],
    },
  },

  {
    msg      => '-dt_on_or_after works',
    search   => { 'me.created_on' => { -dt_on_or_after => '2010-12-14 12:12:12' } },
    select   => [ [ -ident => 'me.created_on' ] ],
    as       => [ 'date' ],
    select_sql => "me.created_on",
    where    => "me.created_on >= ?",
    bind     => [[{dbic_colname => 'me.created_on', sqlt_datatype => 'timestamp' }, '2010-12-14 12:12:12']],
    hri      => [{ date => '2010-12-14 12:12:12' }, { date => '2011-12-14 12:12:12' }],
    sqlite   => { },
    postgres => { },
    mysql    => { },
    mssql    => {
      hri => [{ date => '2010-12-14 12:12:12.000' }, { date => '2011-12-14 12:12:12.000' }],
    },
    oracle   => {
      hri => [{ date => '2010-12-14 12:12:12.000000' }, { date => '2011-12-14 12:12:12.000000' }],
    },
  },

  {
    msg      => '-dt_on_or_after works with DateTime obj',
    search   => { 'me.created_on' => { -dt_on_or_after => $date } },
    select   => [ [ -ident => 'me.created_on' ] ],
    as       => [ 'date' ],
    select_sql => "me.created_on",
    where    => "me.created_on >= ?",
    bind     => [[{sqlt_datatype => 'timestamp' }, '2010-12-14 12:12:12']],
    hri      => [{ date => '2010-12-14 12:12:12' }, { date => '2011-12-14 12:12:12' }],
    sqlite   => { },
    postgres => { },
    mysql    => { },
    mssql    => {
      hri => [{ date => '2010-12-14 12:12:12.000' }, { date => '2011-12-14 12:12:12.000' }],
      bind => [[{sqlt_datatype => 'timestamp' }, '2010-12-14 12:12:12.000']],
    },
    oracle   => {
      hri => [{ date => '2010-12-14 12:12:12.000000' }, { date => '2011-12-14 12:12:12.000000' }],
    },
  },

);

for my $t (@tests) {

  DB_TEST:
  for my $db (keys %rs) {
     my $db_test = $t->{$db};
     unless ($db_test) {
        ok 0, "$t->{msg} ($db not tested!)";
        next DB_TEST;
     }

     my ($r, $my_rs);

     my $cref = sub {
       my $stuff = {
         ( exists $t->{select}
           ? ( select => $t->{select}, as => $t->{as} )
           : ( columns => [qw(starts_at created_on skip_inflation)] )
         )
       };
       $my_rs = $rs{$db}->search($t->{search}, $stuff);
       $r = $my_rs->as_query
     };

     if ($db_test->{exception_like}) {
       throws_ok(
         sub { $cref->() },
         $db_test->{exception_like},
         "throws the expected exception ($db_test->{exception_like})",
       );
     } else {
       if ($db_test->{warning_like}) {
         warning_like(
           sub { $cref->() },
           $db_test->{warning_like},
           "issues the expected warning ($db_test->{warning_like})"
         );
       }
       else {
         $cref->();
       }
       is_same_sql_bind(
         $r,
         '(SELECT ' . ($db_test->{select} || $t->{select_sql}) . ' FROM event me WHERE ' . ($db_test->{where} || $t->{where}) . ')',
         $db_test->{bind} || $t->{bind},
         ($t->{msg} ? "$t->{msg} ($db)" : ())
       );

       SKIP: {
       if (my $hri = $db_test->{hri} || $t->{hri}) {
          skip "Cannot test database we are not connected to ($db)", 1 unless $dbs_to_test{$db};
          skip $db_test->{skip} . " ($db)", 1 if $db_test->{skip};

          my $msg = ($t->{msg} ? "$t->{msg} ($db actually pulls expected data)" : '');
          try {
             my $got = [ $my_rs->hri_dump->all ];
             my $success = is_deeply $got, $hri, $msg;
             unless ($success) {
                warn "$db: $t->{msg} got:      " . Dumper $got;
                warn "$db: $t->{msg} expected: " . Dumper $hri;
             }
          } catch {
             ok 0, $msg . " $_";
          }
        } }
     }
  }
}

done_testing;
