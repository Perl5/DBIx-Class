sub run_tests {

plan tests => 1;

DBICTest->class("Artist")->load_components(qw/PK::Auto::SQLite/);

# add an artist without primary key to test Auto
my $artist = DBICTest->class("Artist")->create( { name => 'Auto' } );
$artist->name( 'Auto Change' );
ok($artist->update, 'update on object created without PK ok');

}

1;
