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
  DBICTest::Schema::Artist->add_column('parentid' => { data_type => 'integer', is_nullable => 0 });

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

$schema->txn_do( sub {
$schema->deploy;
### test hierarchical queries
#{
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
#}
});

done_testing;
