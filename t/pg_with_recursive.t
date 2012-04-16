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
use DBICTest::Schema::Artist;
BEGIN {
  DBICTest::Schema::Artist->add_column('parentid' => { data_type => 'integer', is_nullable => 1 });

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
my ($dsn, $user,  $pass)  = @ENV{map { "DBICTEST_PG_${_}" }  qw/DSN USER PASS/};
my $schema = DBICTest::Schema->connect($dsn, $user, $pass);

note "Pg Version: " . $schema->storage->_server_info->{dbms_version};

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

  # begin tests
  {
    my $search_stuff = {
      with_recursive => {
        -columns    => [qw( artistid parentid name rank )],
        -initial    => $schema->resultset('Artist')->find({ name => 'root' }),
        -recursive  => $schema->resultset('Artist')->search({}),
      }
    };
    # select the whole tree
    my $rs = $schema->resultset('Artist')->search({}, $search_stuff);
  }
}

sub do_creates {
  my ( $dbh, $q ) = @_;
  do_clean($dbh);
  $dbh->do(qq{
    BEGIN;
    CREATE TABLE "artist" (
      "parentid" integer,
      "artistid" serial NOT NULL,
      "name" character varying(100),
      "rank" integer DEFAULT 13 NOT NULL,
      "charfield" character(10),
      PRIMARY KEY ("artistid"),
      CONSTRAINT "artist_name" UNIQUE ("name"),
      CONSTRAINT "u_nullable" UNIQUE ("charfield", "rank")
    );

    CREATE TABLE "cd" (
      "cdid" serial NOT NULL,
      "artist" integer NOT NULL,
      "title" character varying(100) NOT NULL,
      "year" character varying(100) NOT NULL,
      "genreid" integer,
      "single_track" integer,
      PRIMARY KEY ("cdid"),
      CONSTRAINT "cd_artist_title" UNIQUE ("artist", "title")
    );
    CREATE INDEX "cd_idx_artist" on "cd" ("artist");
    CREATE INDEX "cd_idx_genreid" on "cd" ("genreid");
    CREATE INDEX "cd_idx_single_track" on "cd" ("single_track");

    CREATE TABLE "track" (
      "trackid" serial NOT NULL,
      "cd" integer NOT NULL,
      "position" integer NOT NULL,
      "title" character varying(100) NOT NULL,
      "last_updated_on" timestamp,
      "last_updated_at" timestamp,
      PRIMARY KEY ("trackid"),
      CONSTRAINT "track_cd_position" UNIQUE ("cd", "position"),
      CONSTRAINT "track_cd_title" UNIQUE ("cd", "title")
    );
    CREATE INDEX "track_idx_cd" on "track" ("cd");
    COMMIT;
  });

}

sub do_clean {
  my $dbh = shift;
  eval {
    $dbh->do(qq{
      DROP TABLE "artist" CASCADE;
      DROP TABLE "cd" CASCADE;
      DROP TABLE "track" CASCADE;
    });
  };
}
END {
  for ($dbh) {
    next unless $_;
    local $SIG{__WARN__} = sub {};
    do_clean($_);
  }
  undef $dbh;
}
done_testing;
