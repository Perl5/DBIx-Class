use Test::More;

use DBIx::Class::PK::Auto;
use DBIx::Class::PK::Auto::SQLite;

plan tests => 2;

use lib qw(t/lib);

use_ok('DBICTest');

unshift(@DBICTest::Artist::ISA, qw/DBIx::Class::PK::Auto
                                   DBIx::Class::PK::Auto::SQLite/);

# add an artist without primary key to test Auto
my $artist = DBICTest::Artist->create( { name => 'Auto' } );
$artist->name( 'Auto Change' );
ok($artist->update, 'update on object created without PK ok');
