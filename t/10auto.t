use Test::More;

plan tests => 2;

use lib qw(t/lib);

use_ok('DBICTest');

DBICTest::Artist->load_components(qw/PK::Auto::SQLite/);

# add an artist without primary key to test Auto
my $artist = DBICTest::Artist->create( { name => 'Auto' } );
$artist->name( 'Auto Change' );
ok($artist->update, 'update on object created without PK ok');
