use strict;
use warnings;

use Test::Exception;
use Test::More;
use Sub::Name;
use Try::Tiny;
use DBIx::Class::Optional::Dependencies ();

use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;

my ($dsn,  $user,  $pass)  = @ENV{map { "DBICTEST_ORA_${_}" }  qw/DSN USER PASS/};

# optional:
my ($dsn2, $user2, $pass2) = @ENV{map { "DBICTEST_ORA_EXTRAUSER_${_}" } qw/DSN USER PASS/};

plan skip_all => 'Set $ENV{DBICTEST_ORA_DSN}, _USER and _PASS to run this test.'
  unless ($dsn && $user && $pass);

plan skip_all => 'Test needs ' . DBIx::Class::Optional::Dependencies->req_missing_for ('test_rdbms_oracle')
  unless DBIx::Class::Optional::Dependencies->req_ok_for ('test_rdbms_oracle');

$ENV{NLS_SORT} = "BINARY";
$ENV{NLS_COMP} = "BINARY";
$ENV{NLS_LANG} = "AMERICAN";

{
  package    # hide from PAUSE
    DBICTest::Schema::ArtistFQN;

  use base 'DBIx::Class::Core';

  __PACKAGE__->table(
    $ENV{DBICTEST_ORA_USER}
      ? (uc $ENV{DBICTEST_ORA_USER}) . '.artist'
      : '??_no_user_??'
  );
  __PACKAGE__->add_columns(
    'artistid' => {
      data_type         => 'integer',
      is_auto_increment => 1,
    },
    'name' => {
      data_type   => 'varchar',
      size        => 100,
      is_nullable => 1,
    },
    'autoinc_col' => {
      data_type         => 'integer',
      is_auto_increment => 1,
    },
    'default_value_col' => {
      data_type           => 'varchar',
      size                => 100,
      is_nullable         => 0,
      retrieve_on_insert  => 1,
    }
  );
  __PACKAGE__->set_primary_key(qw/ artistid autoinc_col /);

  1;
}

DBICTest::Schema->load_classes('ArtistFQN');

# This is in Core now, but it's here just to test that it doesn't break
DBICTest::Schema::Artist->load_components('PK::Auto');
# These are compat shims for PK::Auto...
DBICTest::Schema::CD->load_components('PK::Auto::Oracle');
DBICTest::Schema::Track->load_components('PK::Auto::Oracle');


# check if we indeed do support stuff
my $v = do {
  my $v = DBICTest::Schema->connect($dsn, $user, $pass)->storage->_dbh_get_info(18);
  $v =~ /^(\d+)\.(\d+)/
    or die "Unparseable Oracle server version: $v\n";

  sprintf('%d.%03d', $1, $2);
};

my $test_server_supports_only_orajoins = $v < 9;

# TODO find out which version supports the RETURNING syntax
# 8i (8.1) has it and earlier docs are a 404 on oracle.com
my $test_server_supports_insert_returning = $v >= 8.001;

is (
  DBICTest::Schema->connect($dsn, $user, $pass)->storage->_use_insert_returning,
  $test_server_supports_insert_returning,
  'insert returning capability guessed correctly'
);

##########
# the recyclebin (new for 10g) sometimes comes in the way
my $on_connect_sql = $v >= 10 ? ["ALTER SESSION SET recyclebin = OFF"] : [];

# iterate all tests on following options
my @tryopt = (
  { on_connect_do => $on_connect_sql },
  { quote_char => '"', on_connect_do => $on_connect_sql },
);

# keep a database handle open for cleanup
my ($dbh, $dbh2);

my $schema;
for my $use_insert_returning ($test_server_supports_insert_returning ? (1,0) : (0) ) {
  for my $force_ora_joins ($test_server_supports_only_orajoins ? (0) : (0,1) ) {

    no warnings qw/once/;
    local *DBICTest::Schema::connection = subname 'DBICTest::Schema::connection' => sub {
      my $s = shift->next::method (@_);
      $s->storage->_use_insert_returning ($use_insert_returning);
      $s->storage->sql_maker_class('DBIx::Class::SQLMaker::OracleJoins') if $force_ora_joins;
      $s;
    };

    for my $opt (@tryopt) {
      # clean all cached sequences from previous run
      for (map { values %{DBICTest::Schema->source($_)->columns_info} } (qw/Artist CD Track/) ) {
        delete $_->{sequence};
      }

      my $schema = DBICTest::Schema->connect($dsn, $user, $pass, $opt);

      $dbh = $schema->storage->dbh;
      my $q = $schema->storage->sql_maker->quote_char || '';

      do_creates($dbh, $q);

      _run_tests($schema, $opt);
    }
  }
}

sub _run_tests {
  my ($schema, $opt) = @_;

  my $q = $schema->storage->sql_maker->quote_char || '';

# test primary key handling with multiple triggers
  my ($new, $seq);

  my $new_artist = $schema->resultset('Artist')->create({ name => 'foo' });
  my $new_cd     = $schema->resultset('CD')->create({ artist => 1, title => 'EP C', year => '2003' });

  SKIP: {
    skip 'not detecting sequences when using INSERT ... RETURNING', 4
      if $schema->storage->_use_insert_returning;

    is($new_artist->artistid, 1, "Oracle Auto-PK worked for standard sqlt-like trigger");
    $seq = $new_artist->result_source->column_info('artistid')->{sequence};
    $seq = $$seq if ref $seq;
    like ($seq, qr/\.${q}artist_pk_seq${q}$/, 'Correct PK sequence selected for sqlt-like trigger');

    is($new_cd->cdid, 1, 'Oracle Auto-PK worked - using scalar ref as table name/custom weird trigger');
    $seq = $new_cd->result_source->column_info('cdid')->{sequence};
    $seq = $$seq if ref $seq;
    like ($seq, qr/\.${q}cd_seq${q}$/, 'Correct PK sequence selected for custom trigger');
  }

# test PKs again with fully-qualified table name
  my $artistfqn_rs = $schema->resultset('ArtistFQN');
  my $artist_rsrc = $artistfqn_rs->result_source;

  delete $artist_rsrc->column_info('artistid')->{sequence};
  $new = $artistfqn_rs->create( { name => 'bar' } );

  is_deeply( {map { $_ => $new->$_ } $artist_rsrc->primary_columns},
    { artistid => 2, autoinc_col => 2},
    "Oracle Multi-Auto-PK worked with fully-qualified tablename" );


  delete $artist_rsrc->column_info('artistid')->{sequence};
  $new = $artistfqn_rs->create( { name => 'bar', autoinc_col => 1000 } );

  is( $new->artistid, 3, "Oracle Auto-PK worked with fully-qualified tablename" );
  is( $new->autoinc_col, 1000, "Oracle Auto-Inc overruled with fully-qualified tablename");


  is( $new->default_value_col, 'default_value', $schema->storage->_use_insert_returning
    ? 'Check retrieve_on_insert on default_value_col with INSERT ... RETURNING'
    : 'Check retrieve_on_insert on default_value_col without INSERT ... RETURNING'
  );

  SKIP: {
    skip 'not detecting sequences when using INSERT ... RETURNING', 1
      if $schema->storage->_use_insert_returning;

    $seq = $new->result_source->column_info('artistid')->{sequence};
    $seq = $$seq if ref $seq;
    like ($seq, qr/\.${q}artist_pk_seq${q}$/, 'Correct PK sequence selected for sqlt-like trigger');
  }


# test LIMIT support
  for (1..6) {
    $schema->resultset('Artist')->create({ name => 'Artist ' . $_ });
  }
  my $it = $schema->resultset('Artist')->search( { name => { -like => 'Artist %' } }, {
    rows => 3,
    offset => 4,
    order_by => 'artistid'
  });

  is( $it->count, 2, "LIMIT count past end of RS ok" );
  is( $it->next->name, "Artist 5", "iterator->next ok" );
  is( $it->next->name, "Artist 6", "iterator->next ok" );
  is( $it->next, undef, "next past end of resultset ok" );

# test identifiers over the 30 char limit
  lives_ok {
    my @results = $schema->resultset('CD')->search(undef, {
      prefetch => 'very_long_artist_relationship',
      rows => 3,
      offset => 0,
    })->all;
    ok( scalar @results > 0, 'limit with long identifiers returned something');
  } 'limit with long identifiers executed successfully';


# test rel names over the 30 char limit
  my $query = $schema->resultset('Artist')->search({
    artistid => 1
  }, {
    prefetch => 'cds_very_very_very_long_relationship_name'
  });

  lives_and {
    is $query->first->cds_very_very_very_long_relationship_name->first->cdid, 1
  } 'query with rel name over 30 chars survived and worked';

# test rel names over the 30 char limit using group_by and join
  {
    my @group_cols = ( 'me.name' );
    my $query = $schema->resultset('Artist')->search({
      artistid => 1
    }, {
      select => \@group_cols,
      as => [map { /^\w+\.(\w+)$/ } @group_cols],
      join => [qw( cds_very_very_very_long_relationship_name )],
      group_by => \@group_cols,
    });

    lives_and {
      my @got = $query->get_column('name')->all();
      is_deeply \@got, [$new_artist->name];
    } 'query with rel name over 30 chars worked on join, group_by for me col';

    lives_and {
      is $query->count(), 1
    } 'query with rel name over 30 chars worked on join, group_by, count for me col';
  }
  {
    my @group_cols = ( 'cds_very_very_very_long_relationship_name.title' );
    my $query = $schema->resultset('Artist')->search({
      artistid => 1
    }, {
      select => \@group_cols,
      as => [map { /^\w+\.(\w+)$/ } @group_cols],
      join => [qw( cds_very_very_very_long_relationship_name )],
      group_by => \@group_cols,
    });

    lives_and {
      my @got = $query->get_column('title')->all();
      is_deeply \@got, [$new_cd->title];
    } 'query with rel name over 30 chars worked on join, group_by for long rel col';

    lives_and {
      is $query->count(), 1
    } 'query with rel name over 30 chars worked on join, group_by, count for long rel col';
  }

  # rel name over 30 char limit with user condition
  # This requires walking the SQLA data structure.
  {
    $query = $schema->resultset('Artist')->search({
      'cds_very_very_very_long_relationship_name.title' => 'EP C'
    }, {
      prefetch => 'cds_very_very_very_long_relationship_name'
    });

    lives_and {
      is $query->first->cds_very_very_very_long_relationship_name->first->cdid, 1
    } 'query with rel name over 30 chars and user condition survived and worked';
  }


# test join with row count ambiguity
  my $cd = $schema->resultset('CD')->next;
  my $track = $cd->create_related('tracks', { position => 1, title => 'Track1'} );
  my $tjoin = $schema->resultset('Track')->search({ 'me.title' => 'Track1'}, {
    join => 'cd', rows => 2
  });

  ok(my $row = $tjoin->next);

  is($row->title, 'Track1', "ambiguous column ok");



# check count distinct with multiple columns
  my $other_track = $schema->resultset('Track')->create({ cd => $cd->cdid, position => 1, title => 'Track2' });

  my $tcount = $schema->resultset('Track')->search(
    {},
    {
      select => [ qw/position title/ ],
      distinct => 1,
    }
  );
  is($tcount->count, 2, 'multiple column COUNT DISTINCT ok');

  $tcount = $schema->resultset('Track')->search(
    {},
    {
      columns => [ qw/position title/ ],
      distinct => 1,
    }
  );
  is($tcount->count, 2, 'multiple column COUNT DISTINCT ok');

  $tcount = $schema->resultset('Track')->search(
    {},
    {
      group_by => [ qw/position title/ ]
    }
  );
  is($tcount->count, 2, 'multiple column COUNT DISTINCT using column syntax ok');


# check group_by
  my $g_rs = $schema->resultset('Track')->search( undef, { columns=>[qw/trackid position/], group_by=> [ qw/trackid position/ ] , rows => 2, offset => 1 });
  is( scalar $g_rs->all, 1, "Group by with limit OK" );


# test with_deferred_fk_checks
  lives_ok {
    $schema->storage->with_deferred_fk_checks(sub {
      $schema->resultset('Track')->create({
        trackid => 999, cd => 999, position => 1, title => 'deferred FK track'
      });
      $schema->resultset('CD')->create({
        artist => 1, cdid => 999, year => '2003', title => 'deferred FK cd'
      });
    });
  } 'with_deferred_fk_checks code survived';

  is eval { $schema->resultset('Track')->find(999)->title }, 'deferred FK track',
    'code in with_deferred_fk_checks worked';

  throws_ok {
    $schema->resultset('Track')->create({
      trackid => 1, cd => 9999, position => 1, title => 'Track1'
    });
  } qr/constraint/i, 'with_deferred_fk_checks is off';


# test auto increment using sequences WITHOUT triggers
  for (1..5) {
    my $st = $schema->resultset('SequenceTest')->create({ name => 'foo' });
    is($st->pkid1, $_, "Oracle Auto-PK without trigger: First primary key");
    is($st->pkid2, $_ + 9, "Oracle Auto-PK without trigger: Second primary key");
    is($st->nonpkid, $_ + 19, "Oracle Auto-PK without trigger: Non-primary key");
  }
  my $st = $schema->resultset('SequenceTest')->create({ name => 'foo', pkid1 => 55 });
  is($st->pkid1, 55, "Oracle Auto-PK without trigger: First primary key set manually");


# test BLOBs
  SKIP: {
  TODO: {
    my %binstr = ( 'small' => join('', map { chr($_) } ( 1 .. 127 )) );
    $binstr{'large'} = $binstr{'small'} x 1024;

    my $maxloblen = (length $binstr{'large'}) + 5;
    note "Localizing LongReadLen to $maxloblen to avoid truncation of test data";
    local $dbh->{'LongReadLen'} = $maxloblen;

    my $rs = $schema->resultset('BindType');

    if ($DBD::Oracle::VERSION eq '1.23') {
      throws_ok { $rs->create({ id => 1, blob => $binstr{large} }) }
        qr/broken/,
        'throws on blob insert with DBD::Oracle == 1.23';

      skip 'buggy BLOB support in DBD::Oracle 1.23', 1;
    }

    # disable BLOB mega-output
    my $orig_debug = $schema->storage->debug;

    local $TODO = 'Something is confusing column bindtype assignment when quotes are active'
                . ': https://rt.cpan.org/Ticket/Display.html?id=64206'
      if $q;

    my $id;
    foreach my $size (qw( small large )) {
      $id++;

      if ($size eq 'small') {
        $schema->storage->debug($orig_debug);
      }
      elsif ($size eq 'large') {
        $schema->storage->debug(0);
      }

      my $str = $binstr{$size};
      lives_ok {
        $rs->create( { 'id' => $id, blob => "blob:$str", clob => "clob:$str" } )
      } "inserted $size without dying";

      my %kids = %{$schema->storage->_dbh->{CachedKids}};
      my @objs = $rs->search({ blob => "blob:$str", clob => "clob:$str" })->all;
      is_deeply (
        $schema->storage->_dbh->{CachedKids},
        \%kids,
        'multi-part LOB equality query was not cached',
      ) if $size eq 'large';
      is @objs, 1, 'One row found matching on both LOBs';
      ok (try { $objs[0]->blob }||'' eq "blob:$str", 'blob inserted/retrieved correctly');
      ok (try { $objs[0]->clob }||'' eq "clob:$str", 'clob inserted/retrieved correctly');

      TODO: {
        local $TODO = '-like comparison on blobs not tested before ora 10 (fails on 8i)'
          if $schema->storage->_server_info->{normalized_dbms_version} < 10;

        lives_ok {
          @objs = $rs->search({ clob => { -like => 'clob:%' } })->all;
          ok (@objs, 'rows found matching CLOB with a LIKE query');
        } 'Query with like on blob succeeds';
      }

      ok(my $subq = $rs->search(
        { blob => "blob:$str", clob => "clob:$str" },
        {
          from => \ "(SELECT * FROM ${q}bindtype_test${q} WHERE ${q}id${q} != ?) ${q}me${q}",
          bind => [ [ undef => 12345678 ] ],
        }
      )->get_column('id')->as_query);

      @objs = $rs->search({ id => { -in => $subq } })->all;
      is (@objs, 1, 'One row found matching on both LOBs as a subquery');

      lives_ok {
        $rs->search({ id => $id, blob => "blob:$str", clob => "clob:$str" })
          ->update({ blob => 'updated blob', clob => 'updated clob' });
      } 'blob UPDATE with blobs in WHERE clause survived';

      @objs = $rs->search({ blob => "updated blob", clob => 'updated clob' })->all;
      is @objs, 1, 'found updated row';
      ok (try { $objs[0]->blob }||'' eq "updated blob", 'blob updated/retrieved correctly');
      ok (try { $objs[0]->clob }||'' eq "updated clob", 'clob updated/retrieved correctly');

      lives_ok {
        $rs->search({ id => $id  })
          ->update({ blob => 're-updated blob', clob => 're-updated clob' });
      } 'blob UPDATE without blobs in WHERE clause survived';

      @objs = $rs->search({ blob => 're-updated blob', clob => 're-updated clob' })->all;
      is @objs, 1, 'found updated row';
      ok (try { $objs[0]->blob }||'' eq 're-updated blob', 'blob updated/retrieved correctly');
      ok (try { $objs[0]->clob }||'' eq 're-updated clob', 'clob updated/retrieved correctly');

      lives_ok {
        $rs->search({ blob => "re-updated blob", clob => "re-updated clob" })
          ->delete;
      } 'blob DELETE with WHERE clause survived';
      @objs = $rs->search({ blob => "re-updated blob", clob => 're-updated clob' })->all;
      is @objs, 0, 'row deleted successfully';
    }

    $schema->storage->debug ($orig_debug);
  }}

# test populate (identity, success and error handling)
  my $art_rs = $schema->resultset('Artist');

  my $seq_pos = $art_rs->get_column('artistid')->max;
  ok($seq_pos, 'Starting with something in the artist table');


  my $pop_rs = $schema->resultset('Artist')->search(
    { name => { -like => 'pop_art_%' } },
    { order_by => 'artistid' }
  );

  $art_rs->delete;
  lives_ok {
    $pop_rs->populate([
      map { +{ name => "pop_art_$_" } }
      (1,2,3)
    ]);

    is_deeply (
      [ $pop_rs->get_column('artistid')->all ],
      [ map { $seq_pos + $_ } (1,2,3) ],
      'Sequence works after empty-table insertion'
    );
  } 'Populate without identity does not throw';

  lives_ok {
    $pop_rs->populate([
      map { +{ artistid => $_, name => "pop_art_$_" } }
      (1,2,3)
    ]);

    is_deeply (
      [ $pop_rs->get_column('artistid')->all ],
      [ 1,2,3, map { $seq_pos + $_ } (1,2,3) ],
      'Explicit id population works'
    );
  } 'Populate with identity does not throw';

  throws_ok {
    $pop_rs->populate([
      map { +{ artistid => $_, name => "pop_art_$_" } }
      (200, 1, 300)
    ]);
  } qr/unique constraint.+populate slice.+name => "pop_art_1"/s, 'Partially failed populate throws';

  is_deeply (
    [ $pop_rs->get_column('artistid')->all ],
    [ 1,2,3, map { $seq_pos + $_ } (1,2,3) ],
    'Partially failed populate did not alter table contents'
  );

# test complex join (exercise orajoins)
  lives_ok {
    my @hri = $schema->resultset('CD')->search(
      { 'artist.name' => 'pop_art_1', 'me.cdid' => { '!=', 999} },
      { join => 'artist', prefetch => 'tracks', rows => 4, order_by => 'tracks.trackid' }
    )->hri_dump->all;

    my $expect = [{
      artist => 1,
      cdid => 1,
      genreid => undef,
      single_track => undef,
      title => "EP C",
      tracks => [
        {
          cd => 1,
          last_updated_at => undef,
          last_updated_on => undef,
          position => 1,
          title => "Track1",
          trackid => 1
        },
        {
          cd => 1,
          last_updated_at => undef,
          last_updated_on => undef,
          position => 1,
          title => "Track2",
          trackid => 2
        },
      ],
      year => 2003
    }];

    is_deeply (
      \@hri,
      $expect,
      'Correct set of data prefetched',
    );

  } 'complex prefetch ok';

# test sequence detection from a different schema
  SKIP: {
  TODO: {
    skip ((join '',
      'Set DBICTEST_ORA_EXTRAUSER_DSN, _USER and _PASS to a *DIFFERENT* Oracle user',
      ' to run the cross-schema sequence detection test.'),
    1) unless $dsn2 && $user2 && $user2 ne $user;

    skip 'not detecting cross-schema sequence name when using INSERT ... RETURNING', 1
      if $schema->storage->_use_insert_returning;

    # Oracle8i Reference Release 2 (8.1.6)
    #   http://download.oracle.com/docs/cd/A87860_01/doc/server.817/a76961/ch294.htm#993
    # Oracle Database Reference 10g Release 2 (10.2)
    #   http://download.oracle.com/docs/cd/B19306_01/server.102/b14237/statviews_2107.htm#sthref1297
    local $TODO = "On Oracle8i all_triggers view is empty, i don't yet know why..."
      if $schema->storage->_server_info->{normalized_dbms_version} < 9;

    my $schema2 = $schema->connect($dsn2, $user2, $pass2, $opt);
    my $dbh2 = $schema2->storage->dbh;

    # create identically named tables/sequences in the other schema
    do_creates($dbh2, $q);

    # grand select privileges to the 2nd user
    $dbh->do("GRANT INSERT ON ${q}artist${q} TO " . uc $user2);
    $dbh->do("GRANT SELECT ON ${q}artist${q} TO " . uc $user2);
    $dbh->do("GRANT SELECT ON ${q}artist_pk_seq${q} TO " . uc $user2);
    $dbh->do("GRANT SELECT ON ${q}artist_autoinc_seq${q} TO " . uc $user2);

    # test with a fully qualified table (user1/schema prepended)
    my $rs2 = $schema2->resultset('ArtistFQN');
    delete $rs2->result_source->column_info('artistid')->{sequence};

    lives_and {
      my $row = $rs2->create({ name => 'From Different Schema' });
      ok $row->artistid;
    } 'used autoinc sequence across schemas';

    # now quote the sequence name (do_creates always uses an lc name)
    my $q_seq = $q
      ? '"artist_pk_seq"'
      : '"ARTIST_PK_SEQ"'
    ;
    delete $rs2->result_source->column_info('artistid')->{sequence};
    $dbh->do(qq{
      CREATE OR REPLACE TRIGGER ${q}artist_insert_trg_pk${q}
      BEFORE INSERT ON ${q}artist${q}
      FOR EACH ROW
      BEGIN
        IF :new.${q}artistid${q} IS NULL THEN
          SELECT $q_seq.nextval
          INTO :new.${q}artistid${q}
          FROM DUAL;
        END IF;
      END;
    });


    lives_and {
      my $row = $rs2->create({ name => 'From Different Schema With Quoted Sequence' });
      ok $row->artistid;
    } 'used quoted autoinc sequence across schemas';

    is_deeply $rs2->result_source->column_info('artistid')->{sequence},
      \( (uc $user) . ".$q_seq"),
      'quoted sequence name correctly extracted';

    # try an insert operation on the default user2 artist
    my $art1 = $schema->resultset('Artist');
    my $art2 = $schema2->resultset('Artist');
    my $art1_count = $art1->count || 0;
    my $art2_count = $art2->count;

    is( $art2_count, 0, 'No artists created yet in second schema' );

    delete $art2->result_source->column_info('artistid')->{sequence};
    my $new_art = $art2->create({ name => '2nd best' });

    is ($art1->count, $art1_count, 'No new rows in main schema');
    is ($art2->count, 1, 'One artist create in 2nd schema');

    is( $new_art->artistid, 1, 'Expected first PK' );

    do_clean ($dbh2);
  }}

  do_clean ($dbh);
}

done_testing;

sub do_creates {
  my ($dbh, $q) = @_;

  do_clean($dbh);

  $dbh->do("CREATE SEQUENCE ${q}artist_autoinc_seq${q} START WITH 1 MAXVALUE 999999 MINVALUE 0");
  $dbh->do("CREATE SEQUENCE ${q}artist_pk_seq${q} START WITH 1 MAXVALUE 999999 MINVALUE 0");
  $dbh->do("CREATE SEQUENCE ${q}cd_seq${q} START WITH 1 MAXVALUE 999999 MINVALUE 0");
  $dbh->do("CREATE SEQUENCE ${q}track_seq${q} START WITH 1 MAXVALUE 999999 MINVALUE 0");

  $dbh->do("CREATE SEQUENCE ${q}nonpkid_seq${q} START WITH 20 MAXVALUE 999999 MINVALUE 0");
  # this one is always quoted as per manually specified sequence =>
  $dbh->do('CREATE SEQUENCE "pkid1_seq" START WITH 1 MAXVALUE 999999 MINVALUE 0');
  # this one is always unquoted as per manually specified sequence =>
  $dbh->do("CREATE SEQUENCE pkid2_seq START WITH 10 MAXVALUE 999999 MINVALUE 0");

  $dbh->do("CREATE TABLE ${q}artist${q} (${q}artistid${q} NUMBER(12), ${q}name${q} VARCHAR(255),${q}default_value_col${q} VARCHAR(255) DEFAULT 'default_value', ${q}autoinc_col${q} NUMBER(12), ${q}rank${q} NUMBER(38), ${q}charfield${q} VARCHAR2(10))");
  $dbh->do("ALTER TABLE ${q}artist${q} ADD (CONSTRAINT ${q}artist_pk${q} PRIMARY KEY (${q}artistid${q}))");

  $dbh->do("CREATE TABLE ${q}sequence_test${q} (${q}pkid1${q} NUMBER(12), ${q}pkid2${q} NUMBER(12), ${q}nonpkid${q} NUMBER(12), ${q}name${q} VARCHAR(255))");
  $dbh->do("ALTER TABLE ${q}sequence_test${q} ADD (CONSTRAINT ${q}sequence_test_constraint${q} PRIMARY KEY (${q}pkid1${q}, ${q}pkid2${q}))");

  # table cd will be unquoted => Oracle will see it as uppercase
  $dbh->do("CREATE TABLE cd (${q}cdid${q} NUMBER(12), ${q}artist${q} NUMBER(12), ${q}title${q} VARCHAR(255), ${q}year${q} VARCHAR(4), ${q}genreid${q} NUMBER(12), ${q}single_track${q} NUMBER(12))");
  $dbh->do("ALTER TABLE cd ADD (CONSTRAINT ${q}cd_pk${q} PRIMARY KEY (${q}cdid${q}))");

  $dbh->do("CREATE TABLE ${q}track${q} (${q}trackid${q} NUMBER(12), ${q}cd${q} NUMBER(12) REFERENCES CD(${q}cdid${q}) DEFERRABLE, ${q}position${q} NUMBER(12), ${q}title${q} VARCHAR(255), ${q}last_updated_on${q} DATE, ${q}last_updated_at${q} DATE)");
  $dbh->do("ALTER TABLE ${q}track${q} ADD (CONSTRAINT ${q}track_pk${q} PRIMARY KEY (${q}trackid${q}))");

  $dbh->do("CREATE TABLE ${q}bindtype_test${q} (${q}id${q} integer NOT NULL PRIMARY KEY, ${q}bytea${q} integer NULL, ${q}blob${q} blob NULL, ${q}clob${q} clob NULL, ${q}a_memo${q} integer NULL)");

  $dbh->do(qq{
    CREATE OR REPLACE TRIGGER ${q}artist_insert_trg_auto${q}
    BEFORE INSERT ON ${q}artist${q}
    FOR EACH ROW
    BEGIN
      IF :new.${q}autoinc_col${q} IS NULL THEN
        SELECT ${q}artist_autoinc_seq${q}.nextval
        INTO :new.${q}autoinc_col${q}
        FROM DUAL;
      END IF;
    END;
  });

  $dbh->do(qq{
    CREATE OR REPLACE TRIGGER ${q}artist_insert_trg_pk${q}
    BEFORE INSERT ON ${q}artist${q}
    FOR EACH ROW
    BEGIN
      IF :new.${q}artistid${q} IS NULL THEN
        SELECT ${q}artist_pk_seq${q}.nextval
        INTO :new.${q}artistid${q}
        FROM DUAL;
      END IF;
    END;
  });

  $dbh->do(qq{
    CREATE OR REPLACE TRIGGER ${q}cd_insert_trg${q}
    BEFORE INSERT OR UPDATE ON cd
    FOR EACH ROW

    DECLARE
    tmpVar NUMBER;

    BEGIN
      tmpVar := 0;

      IF :new.${q}cdid${q} IS NULL THEN
        SELECT ${q}cd_seq${q}.nextval
        INTO tmpVar
        FROM dual;

        :new.${q}cdid${q} := tmpVar;
      END IF;
    END;
  });

  $dbh->do(qq{
    CREATE OR REPLACE TRIGGER ${q}track_insert_trg${q}
    BEFORE INSERT ON ${q}track${q}
    FOR EACH ROW
    BEGIN
      IF :new.${q}trackid${q} IS NULL THEN
        SELECT ${q}track_seq${q}.nextval
        INTO :new.${q}trackid${q}
        FROM DUAL;
      END IF;
    END;
  });
}

# clean up our mess
sub do_clean {

  my $dbh = shift || return;

  for my $q ('', '"') {
    my @clean = (
      "DROP TRIGGER ${q}track_insert_trg${q}",
      "DROP TRIGGER ${q}cd_insert_trg${q}",
      "DROP TRIGGER ${q}artist_insert_trg_auto${q}",
      "DROP TRIGGER ${q}artist_insert_trg_pk${q}",
      "DROP SEQUENCE ${q}nonpkid_seq${q}",
      "DROP SEQUENCE ${q}pkid2_seq${q}",
      "DROP SEQUENCE ${q}pkid1_seq${q}",
      "DROP SEQUENCE ${q}track_seq${q}",
      "DROP SEQUENCE ${q}cd_seq${q}",
      "DROP SEQUENCE ${q}artist_autoinc_seq${q}",
      "DROP SEQUENCE ${q}artist_pk_seq${q}",
      "DROP TABLE ${q}bindtype_test${q}",
      "DROP TABLE ${q}sequence_test${q}",
      "DROP TABLE ${q}track${q}",
      "DROP TABLE ${q}cd${q}",
      "DROP TABLE ${q}artist${q}",
    );
    eval { $dbh -> do ($_) } for @clean;
  }
}

END {
  for ($dbh, $dbh2) {
    next unless $_;
    local $SIG{__WARN__} = sub {};
    do_clean($_);
    $_->disconnect;
  }
}
