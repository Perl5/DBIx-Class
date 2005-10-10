sub run_tests {

eval 'use Data::UUID ; 1'
  or plan skip_all, 'Install Data::UUID run this test';

plan tests => 1;
DBICTest::Artist->load_components('UUIDColumns');
DBICTest::Artist->uuid_columns('name');

my $artist = DBICTest::Artist->create( { artistid => 100 } );
like $artist->name, qr/[\w-]{36}/, 'got something like uuid';

}

1;
