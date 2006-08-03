use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

eval 'use utf8; 1'
    or plan skip_all => 'Need utf8 run this test';

plan tests => 3;

DBICTest::Schema::CD->load_components('UTF8Columns');
DBICTest::Schema::CD->utf8_columns('title');
Class::C3->reinitialize();

my $cd = $schema->resultset('CD')->create( { artist => 1, title => 'øni', year => 'foo' } );
ok( utf8::is_utf8( $cd->title ), 'got title with utf8 flag' );
ok( !utf8::is_utf8( $cd->year ), 'got year without utf8 flag' );

my $utf8_char = 'uniuni';
utf8::decode($utf8_char);
$cd->title($utf8_char);
ok( !utf8::is_utf8( $cd->{_column_data}{title} ),
    'store utf8-less chars' );

