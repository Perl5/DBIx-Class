use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

eval 'use Encode ; 1'
    or plan skip_all => 'Install Encode run this test';

plan tests => 3;

DBICTest::Schema::CD->load_components('UTF8Columns');
DBICTest::Schema::CD->utf8_columns('title');
Class::C3->reinitialize();

my $cd = $schema->resultset('CD')->create( { artist => 1, title => 'uni', year => 'foo' } );
ok( Encode::is_utf8( $cd->title ), 'got title with utf8 flag' );
ok( !Encode::is_utf8( $cd->year ), 'got year without utf8 flag' );

my $utf8_char = 'uniuni';
Encode::_utf8_on($utf8_char);
$cd->title($utf8_char);
ok( !Encode::is_utf8( $cd->{_column_data}{title} ),
    'store utf8-less chars' );

