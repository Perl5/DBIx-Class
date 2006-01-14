sub run_tests {
my $schema = shift;

eval 'use Data::UUID ; 1'
  or plan skip_all, 'Install Data::UUID run this test';

plan tests => 1;
DBICTest::Schema::Artist->load_components('UUIDColumns');
DBICTest::Schema::Artist->uuid_columns('name');
Class::C3->reinitialize();

my $artist = $schema->class("Artist")->create( { artistid => 100 } );
like $artist->name, qr/[\w-]{36}/, 'got something like uuid';

}

1;
