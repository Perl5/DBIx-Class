use strict;
use warnings;

use Test::More;
use Test::Warn;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $cd = $schema->resultset("CD")->find(1);
$cd->title('test');

$schema->is_executed_querycount( sub {
  $cd->update;
}, {
  BEGIN => 1,
  UPDATE => 1,
  COMMIT => 1,
}, 'liner_notes (might_have) not prefetched - do not load liner_notes on update' );

my $cd2 = $schema->resultset("CD")->find(2, {prefetch => 'liner_notes'});
$cd2->title('test2');

$schema->is_executed_querycount( sub {
  $cd2->update;
}, {
  BEGIN => 1,
  UPDATE => 1,
  COMMIT => 1,
}, 'liner_notes (might_have) prefetched - do not load liner_notes on update');

warning_like {
  local $ENV{DBIC_DONT_VALIDATE_RELS};

  DBICTest::Schema::Bookmark->might_have(
    linky => 'DBICTest::Schema::Link',
    { "foreign.id" => "self.link" },
  );
}
  qr{"might_have/has_one" must not be on columns with is_nullable set to true},
  'might_have should warn if the self.id column is nullable';

{
  local $ENV{DBIC_DONT_VALIDATE_RELS} = 1;
  warning_is {
    DBICTest::Schema::Bookmark->might_have(
      slinky => 'DBICTest::Schema::Link',
      { "foreign.id" => "self.link" },
    );
  }
  undef,
  'Setting DBIC_DONT_VALIDATE_RELS suppresses nullable relation warnings';
}

done_testing();
