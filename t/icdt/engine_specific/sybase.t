BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }
use DBIx::Class::Optional::Dependencies -skip_all_without => qw( ic_dt test_rdbms_ase );

use strict;
use warnings;

use Test::More;
use Test::Exception;
use DBIx::Class::_Util qw( scope_guard set_subname );

use DBICTest;

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_SYBASE_${_}" } qw/DSN USER PASS/};

DBICTest::Schema->load_classes('EventSmallDT');

my @storage_types = (
  'DBI::Sybase::ASE',
  'DBI::Sybase::ASE::NoBindVars',
);
my $schema;

for my $storage_type (@storage_types) {
  $schema = DBICTest::Schema->clone;

  unless ($storage_type eq 'DBI::Sybase::ASE') { # autodetect
    $schema->storage_type("::$storage_type");
  }
  $schema->connection($dsn, $user, $pass, {
    on_connect_call => 'datetime_setup',
  });

  my $guard = scope_guard { cleanup($schema) };

  $schema->storage->ensure_connected;

  isa_ok( $schema->storage, "DBIx::Class::Storage::$storage_type" );

  eval { $schema->storage->dbh->do("DROP TABLE track") };
  $schema->storage->dbh->do(<<"SQL");
CREATE TABLE track (
    trackid INT IDENTITY PRIMARY KEY,
    cd INT NULL,
    position INT NULL,
    last_updated_at DATETIME NULL
)
SQL
  eval { $schema->storage->dbh->do("DROP TABLE event_small_dt") };
  $schema->storage->dbh->do(<<"SQL");
CREATE TABLE event_small_dt (
    id INT IDENTITY PRIMARY KEY,
    small_dt SMALLDATETIME NULL,
)
SQL

# coltype, column, source, pk, create_extra, datehash
  my @dt_types = (
    ['DATETIME',
     'last_updated_at',
     'Track',
     'trackid',
     { cd => 1 },
     {
      year => 2004,
      month => 8,
      day => 21,
      hour => 14,
      minute => 36,
      second => 48,
      nanosecond => 500000000,
    }],
    ['SMALLDATETIME', # minute precision
     'small_dt',
     'EventSmallDT',
     'id',
     {},
     {
      year => 2004,
      month => 8,
      day => 21,
      hour => 14,
      minute => 36,
    }],
  );

  for my $dt_type (@dt_types) {
    my ($type, $col, $source, $pk, $create_extra, $sample_dt) = @$dt_type;

    ok(my $dt = DateTime->new($sample_dt));

    my $row;
    ok( $row = $schema->resultset($source)->create({
          $col => $dt,
          %$create_extra,
        }));
    ok( $row = $schema->resultset($source)
      ->search({ $pk => $row->$pk }, { select => [$pk, $col] })
      ->first
    );
    is( $row->$col, $dt, "$type roundtrip" );

    cmp_ok( $row->$col->nanosecond, '==', $sample_dt->{nanosecond},
      'DateTime fractional portion roundtrip' )
      if exists $sample_dt->{nanosecond};

    # Testing an ugly half-solution
    #
    # copy() uses get_columns()
    #
    # The values should survive a roundtrip also, but they don't
    # because the Sybase ICDT setup is asymmetric
    # One *has* to force an inflation/deflation cycle to make the
    # values usable to the database
    #
    # This can be done by marking the columns as dirty, and there
    # are tests for this already in t/inflate/serialize.t
    #
    # But even this isn't enough - one has to reload the RDBMS-formatted
    # values once done, otherwise the copy is just as useless... sigh
    #
    # Adding the test here to validate the technique works
    # UGH!
    {
      no warnings 'once';
      local *DBICTest::BaseResult::copy = set_subname 'DBICTest::BaseResult::copy' => sub {
        my $self = shift;

        $self->make_column_dirty($_) for keys %{{ $self->get_inflated_columns }};

        my $cp = $self->next::method(@_);

        $cp->discard_changes({ columns => [ keys %{{ $cp->get_columns }} ] });
      };
      Class::C3->reinitialize if DBIx::Class::_ENV_::OLD_MRO;

      my $cp = $row->copy;
      ok( $cp->in_storage );
      is( $cp->$col, $dt, "$type copy logical roundtrip" );

      $cp->discard_changes({ select => [ $pk, $col ] });
      is( $cp->$col, $dt, "$type copy server roundtrip" );
    }

    Class::C3->reinitialize if DBIx::Class::_ENV_::OLD_MRO;
  }

  # test a computed datetime column
  eval { $schema->storage->dbh->do("DROP TABLE track") };
  $schema->storage->dbh->do(<<"SQL");
CREATE TABLE track (
    trackid INT IDENTITY PRIMARY KEY,
    cd INT NULL,
    position INT NULL,
    title VARCHAR(100) NULL,
    last_updated_on DATETIME NULL,
    last_updated_at AS getdate(),
)
SQL

  my $now = DateTime->now;
  sleep 1;
  my $new_row = $schema->resultset('Track')->create({});
  $new_row->discard_changes;

  lives_and {
    cmp_ok (($new_row->last_updated_at - $now)->seconds, '>=', 1)
  } 'getdate() computed column works';
}

done_testing;

# clean up our mess
sub cleanup {
  my $schema = shift;
  if (my $dbh = eval { $schema->storage->dbh }) {
    $dbh->do('DROP TABLE track');
    $dbh->do('DROP TABLE event_small_dt');
  }
}
