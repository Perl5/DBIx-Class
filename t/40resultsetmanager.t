use strict;
use warnings;
use Test::More;

use lib qw(t/lib);

BEGIN {
  local $SIG{__WARN__} = sub {};
  require DBIx::Class::ResultSetManager;
}

use DBICTest::ResultSetManager;

my $schema = DBICTest::ResultSetManager->compose_namespace('DB');
my $rs = $schema->resultset('Foo');

ok( !DB::Foo->can('bar'), 'Foo class does not have bar method' );
ok( $rs->can('bar'), 'Foo resultset class has bar method' );
isa_ok( $rs, 'DBICTest::ResultSetManager::Foo::_resultset', 'Foo resultset class is correct' );
is( $rs->bar, 'good', 'bar method works' );

done_testing;
