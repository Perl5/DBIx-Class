use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;


my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_PG_${_}" } qw/DSN USER PASS/};

plan skip_all => <<EOM unless $dsn && $user;
Set \$ENV{DBICTEST_PG_DSN}, _USER and _PASS to run this test
( NOTE: This test drops and creates tables called 'artist', 'casecheck',
  'array_test' and 'sequence_test' as well as following sequences:
  'pkid1_seq', 'pkid2_seq' and 'nonpkid_seq''.  as well as following
  schemas: 'testschema', 'anothertestschema', 'yetanothertestschema',
  'unq_nextval_schema', and 'unq_nextval_schema2'
)
EOM

### load any test classes that are defined further down in the file

our @test_classes; #< array that will be pushed into by test classes defined in this file
DBICTest::Schema->load_classes( map {s/.+:://;$_} @test_classes ) if @test_classes;


###  pre-connect tests
{
  my $s = DBICTest::Schema->connect($dsn, $user, $pass);

  ok (!$s->storage->_dbh, 'definitely not connected');

  # Check that datetime_parser returns correctly before we explicitly connect.
 SKIP: {
      eval { require DateTime::Format::Pg };
      skip "DateTime::Format::Pg required", 2 if $@;

      my $store = ref $s->storage;
      is($store, 'DBIx::Class::Storage::DBI', 'Started with generic storage');

      my $parser = $s->storage->datetime_parser;
      is( $parser, 'DateTime::Format::Pg', 'datetime_parser is as expected');
  }


  # make sure sqlt_type overrides work (::Storage::DBI::Pg does this)
  is ($s->storage->sqlt_type, 'PostgreSQL', 'sqlt_type correct pre-connection');
}

### connect, create postgres-specific test schema

my $schema = DBICTest::Schema->connect($dsn, $user, $pass);
my $dbh = $schema->storage->dbh;

drop_test_schema($schema, 'no warn');
create_test_schema($schema);

### begin main tests

###  auto-pk / last_insert_id / sequence discovery
{
    local $SIG{__WARN__} = sub {};
    _cleanup ($schema);

    $schema->source("Artist")->name("testschema.artist");

    # This is in Core now, but it's here just to test that it doesn't break
    $schema->class('Artist')->load_components('PK::Auto');
    cmp_ok( $schema->resultset('Artist')->count, '==', 0, 'this should start with an empty artist table');

    # test that auto-pk also works with the defined search path by
    # un-schema-qualifying the table name
    my $artist_name_save = $schema->source("Artist")->name;
    $schema->source("Artist")->name("artist");

    my $unq_new;
    lives_ok {
        $unq_new = $schema->resultset('Artist')->create({ name => 'baz' });
    } 'insert into unqualified, shadowed table succeeds';

    is($unq_new && $unq_new->artistid, 1, "and got correct artistid");

    my @test_schemas = ( [qw| anothertestschema    1      |],
                         [qw| yetanothertestschema 1      |],
                       );
    foreach my $t ( @test_schemas ) {
        my ($sch_name, $start_num) = @$t;
        #test with anothertestschema
        $schema->source('Artist')->name("$sch_name.artist");
        $schema->source('Artist')->column_info('artistid')->{sequence} = undef; #< clear sequence name cache
        my $another_new;
        lives_ok {
            $another_new = $schema->resultset('Artist')->create({ name => 'Tollbooth Willy'});
            is( $another_new->artistid,$start_num, "got correct artistid for $sch_name")
                or diag "USED SEQUENCE: ".($schema->source('Artist')->column_info('artistid')->{sequence} || '<none>');
        } "$sch_name liid 1 did not die"
            or diag "USED SEQUENCE: ".($schema->source('Artist')->column_info('artistid')->{sequence} || '<none>');
        lives_ok {
            $another_new = $schema->resultset('Artist')->create({ name => 'Adam Sandler'});
            is( $another_new->artistid,$start_num+1, "got correct artistid for $sch_name")
                or diag "USED SEQUENCE: ".($schema->source('Artist')->column_info('artistid')->{sequence} || '<none>');
        } "$sch_name liid 2 did not die"
            or diag "USED SEQUENCE: ".($schema->source('Artist')->column_info('artistid')->{sequence} || '<none>');

    }


    my @todo_schemas = (
                        [qw| unq_nextval_schema   2 |],
                        [qw| unq_nextval_schema2  1 |],
                       );

    foreach my $t ( @todo_schemas ) {
        my ($sch_name, $start_num) = @$t;

        #test with anothertestschema
        $schema->source('Artist')->name("$sch_name.artist");
        $schema->source('Artist')->column_info('artistid')->{sequence} = undef; #< clear sequence name cache
        my $another_new;
        lives_ok {
            $another_new = $schema->resultset('Artist')->create({ name => 'Tollbooth Willy'});
            is( $another_new->artistid,$start_num, "got correct artistid for $sch_name")
                or diag "USED SEQUENCE: ".($schema->source('Artist')->column_info('artistid')->{sequence} || '<none>');
        } "$sch_name liid 1 did not die"
            or diag "USED SEQUENCE: ".($schema->source('Artist')->column_info('artistid')->{sequence} || '<none>');

        lives_ok {
            $another_new = $schema->resultset('Artist')->create({ name => 'Adam Sandler'});
            is( $another_new->artistid,$start_num+1, "got correct artistid for $sch_name")
                or diag "USED SEQUENCE: ".($schema->source('Artist')->column_info('artistid')->{sequence} || '<none>');
        } "$sch_name liid 2 did not die"
            or diag "USED SEQUENCE: ".($schema->source('Artist')->column_info('artistid')->{sequence} || '<none>');
    }

    $schema->source('Artist')->column_info('artistid')->{sequence} = undef; #< clear sequence name cache
    $schema->source("Artist")->name($artist_name_save);
}

lives_ok {
    my $new = $schema->resultset('Artist')->create({ name => 'foo' });
    is($new->artistid, 4, "Auto-PK worked");
    $new = $schema->resultset('Artist')->create({ name => 'bar' });
    is($new->artistid, 5, "Auto-PK worked");
} 'old auto-pk tests did not die either';



### type_info tests

my $test_type_info = {
    'artistid' => {
        'data_type' => 'integer',
        'is_nullable' => 0,
        'size' => 4,
    },
    'name' => {
        'data_type' => 'character varying',
        'is_nullable' => 1,
        'size' => 100,
        'default_value' => undef,
    },
    'rank' => {
        'data_type' => 'integer',
        'is_nullable' => 0,
        'size' => 4,
        'default_value' => 13,

    },
    'charfield' => {
        'data_type' => 'character',
        'is_nullable' => 1,
        'size' => 10,
        'default_value' => undef,
    },
    'arrayfield' => {
        'data_type' => 'integer[]',
        'is_nullable' => 1,
        'size' => undef,
        'default_value' => undef,
    },
};

my $type_info = $schema->storage->columns_info_for('testschema.artist');
my $artistid_defval = delete $type_info->{artistid}->{default_value};
like($artistid_defval,
     qr/^nextval\('([^\.]*\.){0,1}artist_artistid_seq'::(?:text|regclass)\)/,
     'columns_info_for - sequence matches Pg get_autoinc_seq expectations');
is_deeply($type_info, $test_type_info,
          'columns_info_for - column data types');




####### Array tests

BEGIN {
  package DBICTest::Schema::ArrayTest;
  push @main::test_classes, __PACKAGE__;

  use strict;
  use warnings;
  use base 'DBIx::Class';

  __PACKAGE__->load_components(qw/Core/);
  __PACKAGE__->table('testschema.array_test');
  __PACKAGE__->add_columns(qw/id arrayfield/);
  __PACKAGE__->column_info_from_storage(1);
  __PACKAGE__->set_primary_key('id');

}
SKIP: {
  skip "Need DBD::Pg 2.9.2 or newer for array tests", 4 if $DBD::Pg::VERSION < 2.009002;

  lives_ok {
    $schema->resultset('ArrayTest')->create({
      arrayfield => [1, 2],
    });
  } 'inserting arrayref as pg array data';

  lives_ok {
    $schema->resultset('ArrayTest')->update({
      arrayfield => [3, 4],
    });
  } 'updating arrayref as pg array data';

  $schema->resultset('ArrayTest')->create({
    arrayfield => [5, 6],
  });

  my $count;
  lives_ok {
    $count = $schema->resultset('ArrayTest')->search({
      arrayfield => \[ '= ?' => [arrayfield => [3, 4]] ],   #Todo anything less ugly than this?
    })->count;
  } 'comparing arrayref to pg array data does not blow up';
  is($count, 1, 'comparing arrayref to pg array data gives correct result');
}



########## Case check

BEGIN {
  package DBICTest::Schema::Casecheck;
  push @main::test_classes, __PACKAGE__;

  use strict;
  use warnings;
  use base 'DBIx::Class';

  __PACKAGE__->load_components(qw/Core/);
  __PACKAGE__->table('testschema.casecheck');
  __PACKAGE__->add_columns(qw/id name NAME uc_name storecolumn/);
  __PACKAGE__->column_info_from_storage(1);
  __PACKAGE__->set_primary_key('id');

  sub store_column {
    my ($self, $name, $value) = @_;
    $value = '#'.$value if($name eq "storecolumn");
    $self->maybe::next::method($name, $value);
  }
}

# store_column is called once for create() for non sequence columns
ok(my $storecolumn = $schema->resultset('Casecheck')->create({'storecolumn' => 'a'}));
is($storecolumn->storecolumn, '#a'); # was '##a'

my $name_info = $schema->source('Casecheck')->column_info( 'name' );
is( $name_info->{size}, 1, "Case sensitive matching info for 'name'" );

my $NAME_info = $schema->source('Casecheck')->column_info( 'NAME' );
is( $NAME_info->{size}, 2, "Case sensitive matching info for 'NAME'" );

my $uc_name_info = $schema->source('Casecheck')->column_info( 'uc_name' );
is( $uc_name_info->{size}, 3, "Case insensitive matching info for 'uc_name'" );




## Test SELECT ... FOR UPDATE

my $HaveSysSigAction = eval "require Sys::SigAction" && !$@;
if( $HaveSysSigAction ) {
    Sys::SigAction->import( 'set_sig_handler' );
}
SKIP: {
    skip "Sys::SigAction is not available", 3 unless $HaveSysSigAction;
    # create a new schema
    my $schema2 = DBICTest::Schema->connect($dsn, $user, $pass);
    $schema2->source("Artist")->name("testschema.artist");

    $schema->txn_do( sub {
        my $artist = $schema->resultset('Artist')->search(
            {
                artistid => 1
            },
            {
                for => 'update'
            }
        )->first;
        is($artist->artistid, 1, "select for update returns artistid = 1");

        my $artist_from_schema2;
        my $error_ok = 0;
        eval {
            my $h = set_sig_handler( 'ALRM', sub { die "DBICTestTimeout" } );
            alarm(2);
            $artist_from_schema2 = $schema2->resultset('Artist')->find(1);
            $artist_from_schema2->name('fooey');
            $artist_from_schema2->update;
            alarm(0);
        };
        if (my $e = $@) {
            $error_ok = $e =~ /DBICTestTimeout/;
        }

        # Make sure that an error was raised, and that the update failed
        ok($error_ok, "update from second schema times out");
        ok($artist_from_schema2->is_column_changed('name'), "'name' column is still dirty from second schema");
    });
}

SKIP: {
    skip "Sys::SigAction is not available", 3 unless $HaveSysSigAction;
    # create a new schema
    my $schema2 = DBICTest::Schema->connect($dsn, $user, $pass);
    $schema2->source("Artist")->name("testschema.artist");

    $schema->txn_do( sub {
        my $artist = $schema->resultset('Artist')->search(
            {
                artistid => 1
            },
        )->first;
        is($artist->artistid, 1, "select for update returns artistid = 1");

        my $artist_from_schema2;
        my $error_ok = 0;
        eval {
            my $h = set_sig_handler( 'ALRM', sub { die "DBICTestTimeout" } );
            alarm(2);
            $artist_from_schema2 = $schema2->resultset('Artist')->find(1);
            $artist_from_schema2->name('fooey');
            $artist_from_schema2->update;
            alarm(0);
        };
        if (my $e = $@) {
            $error_ok = $e =~ /DBICTestTimeout/;
        }

        # Make sure that an error was NOT raised, and that the update succeeded
        ok(! $error_ok, "update from second schema DOES NOT timeout");
        ok(! $artist_from_schema2->is_column_changed('name'), "'name' column is NOT dirty from second schema");
    });
}


######## other Auto-pk tests

$schema->source("SequenceTest")->name("testschema.sequence_test");
for (1..5) {
    my $st = $schema->resultset('SequenceTest')->create({ name => 'foo' });
    is($st->pkid1, $_, "Oracle Auto-PK without trigger: First primary key");
    is($st->pkid2, $_ + 9, "Oracle Auto-PK without trigger: Second primary key");
    is($st->nonpkid, $_ + 19, "Oracle Auto-PK without trigger: Non-primary key");
}
my $st = $schema->resultset('SequenceTest')->create({ name => 'foo', pkid1 => 55 });
is($st->pkid1, 55, "Oracle Auto-PK without trigger: First primary key set manually");

done_testing;

exit;
END { drop_test_schema($schema) }


######### SUBROUTINES

sub create_test_schema {
    my $schema = shift;
    $schema->storage->dbh_do(sub {
      my (undef,$dbh) = @_;

      local $dbh->{Warn} = 0;

      my $std_artist_table = <<EOS;
(
  artistid serial PRIMARY KEY
  , name VARCHAR(100)
  , rank INTEGER NOT NULL DEFAULT '13'
  , charfield CHAR(10)
  , arrayfield INTEGER[]
)
EOS

      $dbh->do("CREATE SCHEMA testschema");
      $dbh->do("CREATE TABLE testschema.artist $std_artist_table");
      $dbh->do(<<EOS);
CREATE TABLE testschema.sequence_test (
    pkid1 integer
    , pkid2 integer
    , nonpkid integer
    , name VARCHAR(100)
    , CONSTRAINT pk PRIMARY KEY(pkid1, pkid2)
)
EOS
      $dbh->do("CREATE SEQUENCE pkid1_seq START 1 MAXVALUE 999999 MINVALUE 0");
      $dbh->do("CREATE SEQUENCE pkid2_seq START 10 MAXVALUE 999999 MINVALUE 0");
      $dbh->do("CREATE SEQUENCE nonpkid_seq START 20 MAXVALUE 999999 MINVALUE 0");
      $dbh->do(<<EOS);
CREATE TABLE testschema.casecheck (
    id serial PRIMARY KEY
    , "name" VARCHAR(1)
    , "NAME" VARCHAR(2)
    , "UC_NAME" VARCHAR(3)
    , "storecolumn" VARCHAR(10)
)
EOS
      $dbh->do(<<EOS);
CREATE TABLE testschema.array_test (
    id serial PRIMARY KEY
    , arrayfield INTEGER[]
)
EOS
      $dbh->do("CREATE SCHEMA anothertestschema");
      $dbh->do("CREATE TABLE anothertestschema.artist $std_artist_table");
      $dbh->do("CREATE SCHEMA yetanothertestschema");
      $dbh->do("CREATE TABLE yetanothertestschema.artist $std_artist_table");
      $dbh->do('set search_path=testschema,public');
      $dbh->do("CREATE SCHEMA unq_nextval_schema");
      $dbh->do("CREATE SCHEMA unq_nextval_schema2");
      $dbh->do(<<EOS);
 CREATE TABLE unq_nextval_schema.artist
 (
   artistid integer not null default nextval('artist_artistid_seq'::regclass) PRIMARY KEY
   , name VARCHAR(100)
   , rank INTEGER NOT NULL DEFAULT '13'
   , charfield CHAR(10)
   , arrayfield INTEGER[]
 );
EOS
      $dbh->do('set search_path=public,testschema,yetanothertestschema');
      $dbh->do('create sequence public.artist_artistid_seq'); #< in the public schema
      $dbh->do(<<EOS);
 CREATE TABLE unq_nextval_schema2.artist
 (
   artistid integer not null default nextval('public.artist_artistid_seq'::regclass) PRIMARY KEY
   , name VARCHAR(100)
   , rank INTEGER NOT NULL DEFAULT '13'
   , charfield CHAR(10)
   , arrayfield INTEGER[]
 );
EOS
      $dbh->do('set search_path=testschema,public');
  });
}



sub drop_test_schema {
    my ( $schema, $no_warn ) = @_;

    $schema->storage->dbh_do(sub {
        my (undef,$dbh) = @_;

        local $dbh->{Warn} = 0;

        for my $stat (
                      'DROP SCHEMA unq_nextval_schema2 CASCADE',
                      'DROP SEQUENCE public.artist_artistid_seq',
                      'DROP SCHEMA unq_nextval_schema CASCADE',
                      'DROP SCHEMA testschema CASCADE',
                      'DROP SEQUENCE pkid1_seq',
                      'DROP SEQUENCE pkid2_seq',
                      'DROP SEQUENCE nonpkid_seq',
                      'DROP SCHEMA anothertestschema CASCADE',
                      'DROP SCHEMA yetanothertestschema CASCADE',
                     ) {
            eval { $dbh->do ($stat) };
            diag $@ if $@ && !$no_warn;
        }
    });
}

done_testing;
