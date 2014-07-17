use warnings;
use strict;

use Test::More;

use lib qw(t/lib);
use DBICTest;

{
  package # hideee
    DBICTest::CrazyInt;

  use overload
    '0+' => sub { 666 },
    '""' => sub { 999 },
    fallback => 1,
  ;
}

# check DBI behavior when fed a stringifiable/nummifiable value
{
  my $crazynum = bless {}, 'DBICTest::CrazyInt';
  cmp_ok( $crazynum, '==', 666 );
  cmp_ok( $crazynum, 'eq', 999 );

  my $schema = DBICTest->init_schema( no_populate => 1 );
  $schema->storage->dbh_do(sub {
    $_[1]->do('INSERT INTO artist (name) VALUES (?)', {}, $crazynum );
  });

  is( $schema->resultset('Artist')->next->name, 999, 'DBI preferred stringified version' );
}
done_testing;
