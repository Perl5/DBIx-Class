use strict;
use warnings;
use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema(no_populate => 1);
my $ars    = $schema->resultset('Artist');

my $rank = \13;
my $ref1 = \['?', [name => 'foo']];
my $ref2 = \['?', [name => 'bar']];
my $ref3 = \['?', [name => 'baz']];

# do it twice, make sure the args are untouched
for (1,2) {
  $ars->delete;

  lives_ok {
    $ars->create({ artistid => 666, name => $ref1, rank => $rank });
  } 'inserted row using literal sql';

  ok (($ars->search({ name => 'foo' })->first),
    'row was inserted');

  lives_ok {
    $ars->search({ name => { '=' => $ref1} })->update({ name => $ref2, rank => $rank });
  } 'search/updated row using literal sql';

  ok (($ars->search({ name => 'bar' })->first),
    'row was updated');

  lives_ok {
    $ars->populate([{ artistid => 777, name => $ref3, rank => $rank  }]);
  } 'populated row using literal sql';

  ok (($ars->search({ name => 'baz' })->first),
    'row was populated');
}

is_deeply(
  $ref1,
  \['?', [name => 'foo']],
  'ref1 unchanged',
);
is_deeply(
  $ref2,
  \['?', [name => 'bar']],
  'ref2 unchanged',
);
is_deeply(
  $ref3,
  \['?', [name => 'baz']],
  'ref3 unchanged',
);

done_testing;

# vim:sts=2 sw=2:
