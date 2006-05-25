use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

eval 'use Data::UUID ; 1'
  or plan skip_all => 'Install Data::UUID run this test';

plan tests => 1;
DBICTest::Schema::Artist->load_components('UUIDColumns');
DBICTest::Schema::Artist->uuid_columns('name');
Class::C3->reinitialize();

my $artist = $schema->resultset("Artist")->create( { artistid => 100 } );
like $artist->name, qr/[\w-]{36}/, 'got something like uuid';

