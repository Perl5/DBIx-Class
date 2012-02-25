use strict;
use warnings;

use Test::More;
use Test::Exception;
use Try::Tiny;
use DBIx::Class::SQLMaker::LimitDialects;
use DBIx::Class::Optional::Dependencies ();
use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;

plan skip_all => 'Test needs ' . DBIx::Class::Optional::Dependencies->req_missing_for ('test_rdbms_mssql_odbc')
  unless DBIx::Class::Optional::Dependencies->req_ok_for ('test_rdbms_mssql_odbc');

my $OFFSET = DBIx::Class::SQLMaker::LimitDialects->__offset_bindtype;
my $TOTAL  = DBIx::Class::SQLMaker::LimitDialects->__total_bindtype;

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_MSSQL_ODBC_${_}" } qw/DSN USER PASS/};

plan skip_all => 'Set $ENV{DBICTEST_MSSQL_ODBC_DSN}, _USER and _PASS to run this test'
  unless ($dsn && $user);

{
  my $srv_ver = DBICTest::Schema->connect($dsn, $user, $pass)->storage->_server_info->{dbms_version};
  ok ($srv_ver, 'Got a test server version on fresh schema: ' . ($srv_ver||'???') );
}

DBICTest::Schema->load_classes('ArtistGUID');
my $schema = DBICTest::Schema->connect($dsn, $user, $pass);

{
  no warnings 'redefine';
  my $connect_count = 0;
  my $orig_connect = \&DBI::connect;
  local *DBI::connect = sub { $connect_count++; goto &$orig_connect };

  $schema->storage->ensure_connected;

  is( $connect_count, 1, 'only one connection made');
}

isa_ok( $schema->storage, 'DBIx::Class::Storage::DBI::ODBC::Microsoft_SQL_Server' );

{
  my $schema2 = $schema->connect ($schema->storage->connect_info);
  ok (! $schema2->storage->connected, 'a re-connected cloned schema starts unconnected');
}

$schema->storage->_dbh->disconnect;

lives_ok {
  $schema->storage->dbh_do(sub { $_[1]->do('select 1') })
} '_ping works';

my %opts = (
  use_mars =>
    { opts => { on_connect_call => 'use_mars' } },
  use_dynamic_cursors =>
    { opts => { on_connect_call => 'use_dynamic_cursors' }, required => 1 },
  use_server_cursors =>
    { opts => { on_connect_call => 'use_server_cursors' } },
  NO_OPTION =>
    { opts => {}, required => 1 },
);

for my $opts_name (keys %opts) {
  SKIP: {
    my $opts = $opts{$opts_name}{opts};
    $schema = DBICTest::Schema->connect($dsn, $user, $pass, $opts);

    try {
      $schema->storage->ensure_connected
    }
    catch {
      if ($opts{$opts_name}{required}) {
        BAIL_OUT "on_connect_call option '$opts_name' is not functional: $_";
      }
      else {
        skip
"on_connect_call option '$opts_name' not functional in this configuration: $_",
1;
      }
    };

    $schema->storage->dbh_do (sub {
        my ($storage, $dbh) = @_;
        eval { $dbh->do("DROP TABLE artist") };
        $dbh->do(<<'SQL');
CREATE TABLE artist (
   artistid INT IDENTITY NOT NULL,
   name VARCHAR(100),
   rank INT NOT NULL DEFAULT '13',
   charfield CHAR(10) NULL,
   primary key(artistid)
)
SQL
    });

# test Auto-PK
    $schema->resultset('Artist')->search({ name => 'foo' })->delete;

    my $new = $schema->resultset('Artist')->create({ name => 'foo' });

    ok(($new->artistid||0) > 0, "Auto-PK worked for $opts_name");

# Test multiple active statements
    SKIP: {
      skip 'not a multiple active statements configuration', 1
        if $opts_name eq 'plain';

      my $artist_rs = $schema->resultset('Artist');

      $artist_rs->delete;

      $artist_rs->create({ name => "Artist$_" }) for (1..3);

      my $forward  = $artist_rs->search({},
        { order_by => { -asc  => 'artistid' } });
      my $backward = $artist_rs->search({},
        { order_by => { -desc => 'artistid' } });

      my @map = (
        [qw/Artist1 Artist3/], [qw/Artist2 Artist2/], [qw/Artist3 Artist1/]
      );
      my @result;

      while (my $forward_row = $forward->next) {
        my $backward_row = $backward->next;
        push @result, [$forward_row->name, $backward_row->name];
      }

      is_deeply \@result, \@map, "multiple active statements in $opts_name";

      $artist_rs->delete;
    }

# Test populate

    {
      $schema->storage->dbh_do (sub {
        my ($storage, $dbh) = @_;
        eval { $dbh->do("DROP TABLE owners") };
        eval { $dbh->do("DROP TABLE books") };
        $dbh->do(<<'SQL');
CREATE TABLE books (
   id INT IDENTITY (1, 1) NOT NULL,
   source VARCHAR(100),
   owner INT,
   title VARCHAR(10),
   price INT NULL
)

CREATE TABLE owners (
   id INT IDENTITY (1, 1) NOT NULL,
   name VARCHAR(100),
)
SQL
      });

      lives_ok ( sub {
        # start a new connection, make sure rebless works
        my $schema = DBICTest::Schema->connect($dsn, $user, $pass, $opts);
        $schema->populate ('Owners', [
          [qw/id  name  /],
          [qw/1   wiggle/],
          [qw/2   woggle/],
          [qw/3   boggle/],
          [qw/4   fRIOUX/],
          [qw/5   fRUE/],
          [qw/6   fREW/],
          [qw/7   fROOH/],
          [qw/8   fISMBoC/],
          [qw/9   station/],
          [qw/10   mirror/],
          [qw/11   dimly/],
          [qw/12   face_to_face/],
          [qw/13   icarus/],
          [qw/14   dream/],
          [qw/15   dyrstyggyr/],
        ]);
      }, 'populate with PKs supplied ok' );


      lives_ok (sub {
        # start a new connection, make sure rebless works
        # test an insert with a supplied identity, followed by one without
        my $schema = DBICTest::Schema->connect($dsn, $user, $pass, $opts);
        for (2, 1) {
          my $id = $_ * 20 ;
          $schema->resultset ('Owners')->create ({ id => $id, name => "troglodoogle $id" });
          $schema->resultset ('Owners')->create ({ name => "troglodoogle " . ($id + 1) });
        }
      }, 'create with/without PKs ok' );

      is ($schema->resultset ('Owners')->count, 19, 'owner rows really in db' );

      lives_ok ( sub {
        # start a new connection, make sure rebless works
        my $schema = DBICTest::Schema->connect($dsn, $user, $pass, $opts);
        $schema->populate ('BooksInLibrary', [
          [qw/source  owner title   /],
          [qw/Library 1     secrets0/],
          [qw/Library 1     secrets1/],
          [qw/Eatery  1     secrets2/],
          [qw/Library 2     secrets3/],
          [qw/Library 3     secrets4/],
          [qw/Eatery  3     secrets5/],
          [qw/Library 4     secrets6/],
          [qw/Library 5     secrets7/],
          [qw/Eatery  5     secrets8/],
          [qw/Library 6     secrets9/],
          [qw/Library 7     secrets10/],
          [qw/Eatery  7     secrets11/],
          [qw/Library 8     secrets12/],
        ]);
      }, 'populate without PKs supplied ok' );
    }

# test simple, complex LIMIT and limited prefetch support, with both dialects and quote combinations (if possible)
    for my $dialect (
      'Top',
      ($schema->storage->_server_info->{normalized_dbms_version} || 0 ) >= 9
        ? ('RowNumberOver')
        : ()
      ,
    ) {
      for my $quoted (0, 1) {

        $schema = DBICTest::Schema->connect($dsn, $user, $pass, {
            limit_dialect => $dialect,
            %$opts,
            $quoted
              ? ( quote_char => [ qw/ [ ] / ], name_sep => '.' )
              : ()
            ,
          });

        my $test_type = "Dialect:$dialect Quoted:$quoted";

        # basic limit support
        TODO: {
          my $art_rs = $schema->resultset ('Artist');
          $art_rs->delete;
          $art_rs->create({ name => 'Artist ' . $_ }) for (1..6);

          my $it = $schema->resultset('Artist')->search( {}, {
            rows => 4,
            offset => 3,
            order_by => 'artistid',
          });

          is( $it->count, 3, "$test_type: LIMIT count ok" );

          local $TODO = "Top-limit does not work when your limit ends up past the resultset"
            if $dialect eq 'Top';

          is( $it->next->name, 'Artist 4', "$test_type: iterator->next ok" );
          $it->next;
          is( $it->next->name, 'Artist 6', "$test_type: iterator->next ok" );
          is( $it->next, undef, "$test_type: next past end of resultset ok" );
        }

        # plain ordered subqueries throw
        throws_ok (sub {
          $schema->resultset('Owners')->search ({}, { order_by => 'name' })->as_query
        }, qr/ordered subselect encountered/, "$test_type: Ordered Subselect detection throws ok");

        # make sure ordered subselects *somewhat* work
        {
          my $owners = $schema->resultset ('Owners')->search ({}, { order_by => 'name', offset => 2, rows => 3, unsafe_subselect_ok => 1 });
          my $sealed_owners = $owners->as_subselect_rs;

          is_deeply (
            [ map { $_->name } ($sealed_owners->all) ],
            [ map { $_->name } ($owners->all) ],
            "$test_type: Sort preserved from within a subquery",
          );
        }

        {
          my $book_owner_ids = $schema->resultset ('BooksInLibrary')->search ({}, {
            rows => 6,
            offset => 2,
            join => 'owner',
            distinct => 1,
            order_by => 'owner.name',
            unsafe_subselect_ok => 1
          })->get_column ('owner');

          my @ids = $book_owner_ids->all;

          is (@ids, 6, 'Limit works');

          my $book_owners = $schema->resultset ('Owners')->search ({
            id => { -in => $book_owner_ids->as_query }
          });

          TODO: {
            local $TODO = "Correlated limited IN subqueries will probably never preserve order";

            is_deeply (
              [ map { $_->id } ($book_owners->all) ],
              [ $book_owner_ids->all ],
              "$test_type: Sort is preserved across IN subqueries",
            );
          }
        }

        # still even with lost order of IN, we should be getting correct
        # sets
        {
          my $owners = $schema->resultset ('Owners')->search ({}, { order_by => 'name', offset => 2, rows => 3, unsafe_subselect_ok => 1 });
          my $corelated_owners = $owners->result_source->resultset->search (
            {
              id => { -in => $owners->get_column('id')->as_query },
            },
            {
              order_by => 'name' #reorder because of what is shown above
            },
          );

          is (
            join ("\x00", map { $_->name } ($corelated_owners->all) ),
            join ("\x00", map { $_->name } ($owners->all) ),
            "$test_type: With an outer order_by, everything still matches",
          );
        }

        # make sure right-join-side single-prefetch ordering limit works
        {
          my $rs = $schema->resultset ('BooksInLibrary')->search (
            {
              'owner.name' => { '!=', 'woggle' },
            },
            {
              prefetch => 'owner',
              order_by => 'owner.name',
            }
          );
          # this is the order in which they should come from the above query
          my @owner_names = qw/boggle fISMBoC fREW fRIOUX fROOH fRUE wiggle wiggle/;

          is ($rs->all, 8, "$test_type: Correct amount of objects from right-sorted joined resultset");
          is_deeply (
            [map { $_->owner->name } ($rs->all) ],
            \@owner_names,
            "$test_type: Prefetched rows were properly ordered"
          );

          my $limited_rs = $rs->search ({}, {rows => 6, offset => 2, unsafe_subselect_ok => 1});
          is ($limited_rs->count, 6, "$test_type: Correct count of limited right-sorted joined resultset");
          is ($limited_rs->count_rs->next, 6, "$test_type: Correct count_rs of limited right-sorted joined resultset");

          my $queries;
          my $orig_debug = $schema->storage->debug;
          $schema->storage->debugcb(sub { $queries++; });
          $schema->storage->debug(1);

          is_deeply (
            [map { $_->owner->name } ($limited_rs->all) ],
            [@owner_names[2 .. 7]],
            "$test_type: Prefetch-limited rows were properly ordered"
          );
          is ($queries, 1, "$test_type: Only one query with prefetch");

          $schema->storage->debugcb(undef);
          $schema->storage->debug($orig_debug);

          is_deeply (
            [map { $_->name } ($limited_rs->search_related ('owner')->all) ],
            [@owner_names[2 .. 7]],
            "$test_type: Rows are still properly ordered after search_related",
          );
        }

        # try a ->has_many direction with duplicates
        my $owners = $schema->resultset ('Owners')->search (
          {
            'books.id' => { '!=', undef },
            'me.name' => { '!=', 'somebogusstring' },
          },
          {
            prefetch => 'books',
            order_by => [ { -asc => \['name + ?', [ test => 'xxx' ]] }, 'me.id' ], # test bindvar propagation
            group_by => [ map { "me.$_" } $schema->source('Owners')->columns ], # the literal order_by requires an explicit group_by
            rows     => 3,  # 8 results total
            unsafe_subselect_ok => 1,
          },
        );

        my ($sql, @bind) = @${$owners->page(3)->as_query};
        is_same_bind (
          \@bind,
          [
            ($dialect eq 'Top' ? [ { dbic_colname => 'test' } => 'xxx' ] : ()), # the extra re-order bind
            [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'me.name' }
              => 'somebogusstring' ],
            [ { dbic_colname => 'test' }
              => 'xxx' ],
            ($dialect ne 'Top' ? ( [ $OFFSET => 7 ], [ $TOTAL => 9 ] ) : ()), # parameterised RNO
            [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'me.name' }
              => 'somebogusstring' ],
            [ { dbic_colname => 'test' }
              => 'xxx' ],
          ],
        );

        is ($owners->page(1)->all, 3, "$test_type: has_many prefetch returns correct number of rows");
        is ($owners->page(1)->count, 3, "$test_type: has-many prefetch returns correct count");

        is ($owners->page(3)->count, 2, "$test_type: has-many prefetch returns correct count");
        TODO: {
          local $TODO = "Top-limit does not work when your limit ends up past the resultset"
            if $dialect eq 'Top';
          is ($owners->page(3)->all, 2, "$test_type: has_many prefetch returns correct number of rows");
          is ($owners->page(3)->count_rs->next, 2, "$test_type: has-many prefetch returns correct count_rs");
        }


        # try a ->belongs_to direction (no select collapse, group_by should work)
        my $books = $schema->resultset ('BooksInLibrary')->search (
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
        );

        ($sql, @bind) = @${$books->page(3)->as_query};
        is_same_bind (
          \@bind,
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

            # rno(?)
            $dialect ne 'Top' ? ( [ $OFFSET => 5 ], [ $TOTAL => 6 ] ) : (),
            # outer
            [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'owner.name' }
              => 'wiggle' ],
            [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'owner.name' }
              => 'woggle' ],
            [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' }
              => 'Library' ],
          ],
        );

        is ($books->page(1)->all, 2, "$test_type: Prefetched grouped search returns correct number of rows");
        is ($books->page(1)->count, 2, "$test_type: Prefetched grouped search returns correct count");

        is ($books->page(2)->count, 1, "$test_type: Prefetched grouped search returns correct count");
        TODO: {
          local $TODO = "Top-limit does not work when your limit ends up past the resultset"
            if $dialect eq 'Top';
          is ($books->page(2)->all, 1, "$test_type: Prefetched grouped search returns correct number of rows");
          is ($books->page(2)->count_rs->next, 1, "$test_type: Prefetched grouped search returns correct count_rs");
        }
      }
    }


# test GUID columns
    {
      $schema->storage->dbh_do (sub {
        my ($storage, $dbh) = @_;
        eval { $dbh->do("DROP TABLE artist_guid") };
        $dbh->do(<<'SQL');
CREATE TABLE artist_guid (
   artistid UNIQUEIDENTIFIER NOT NULL,
   name VARCHAR(100),
   rank INT NOT NULL DEFAULT '13',
   charfield CHAR(10) NULL,
   a_guid UNIQUEIDENTIFIER,
   primary key(artistid)
)
SQL
      });

      # start disconnected to make sure insert works on an un-reblessed storage
      $schema = DBICTest::Schema->connect($dsn, $user, $pass, $opts);

      my $row;
      lives_ok {
        $row = $schema->resultset('ArtistGUID')->create({ name => 'mtfnpy' })
      } 'created a row with a GUID';

      ok(
        eval { $row->artistid },
        'row has GUID PK col populated',
      );
      diag $@ if $@;

      ok(
        eval { $row->a_guid },
        'row has a GUID col with auto_nextval populated',
      );
      diag $@ if $@;

      my $row_from_db = $schema->resultset('ArtistGUID')
        ->search({ name => 'mtfnpy' })->first;

      is $row_from_db->artistid, $row->artistid,
        'PK GUID round trip';

      is $row_from_db->a_guid, $row->a_guid,
        'NON-PK GUID round trip';
    }

# test MONEY type
    {
      $schema->storage->dbh_do (sub {
        my ($storage, $dbh) = @_;
        eval { $dbh->do("DROP TABLE money_test") };
        $dbh->do(<<'SQL');
CREATE TABLE money_test (
   id INT IDENTITY PRIMARY KEY,
   amount MONEY NULL
)
SQL
      });

      TODO: {
        my $freetds_and_dynamic_cursors = 1
          if $opts_name eq 'use_dynamic_cursors' &&
            $schema->storage->using_freetds;

        local $TODO =
'these tests fail on freetds with dynamic cursors for some reason'
          if $freetds_and_dynamic_cursors;
        local $ENV{DBIC_NULLABLE_KEY_NOWARN} = 1
          if $freetds_and_dynamic_cursors;

        my $rs = $schema->resultset('Money');
        my $row;

        lives_ok {
          $row = $rs->create({ amount => 100 });
        } 'inserted a money value';

        cmp_ok ((try { $rs->find($row->id)->amount })||0, '==', 100,
          'money value round-trip');

        lives_ok {
          $row->update({ amount => 200 });
        } 'updated a money value';

        cmp_ok ((try { $rs->find($row->id)->amount })||0, '==', 200,
          'updated money value round-trip');

        lives_ok {
          $row->update({ amount => undef });
        } 'updated a money value to NULL';

        is try { $rs->find($row->id)->amount }, undef,
          'updated money value to NULL round-trip';
      }
    }
  }
}

done_testing;

# clean up our mess
END {
  if (my $dbh = eval { $schema->storage->_dbh }) {
    eval { $dbh->do("DROP TABLE $_") }
      for qw/artist artist_guid money_test books owners/;
  }
}
# vim:sw=2 sts=2
