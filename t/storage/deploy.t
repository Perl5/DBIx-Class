use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBICTest;

use File::Spec;
use File::Path qw/ mkpath rmtree /;


my $schema = DBICTest->init_schema();

my $var = File::Spec->catfile(qw| t var create_ddl_dir |);
-d $var
    or mkpath($var)
    or die "can't create $var";

my $test_dir_1 =  File::Spec->catdir( $var, 'test1', 'foo', 'bar' );
rmtree( $test_dir_1 ) if -d $test_dir_1;
$schema->create_ddl_dir( undef, undef, $test_dir_1 );

ok( -d $test_dir_1, 'create_ddl_dir did a mkpath on its target dir' );
ok( scalar( glob $test_dir_1.'/*.sql' ), 'there are sql files in there' );

TODO: {
    local $TODO = 'we should probably add some tests here for actual deployability of the DDL?';
    ok( 0 );
}

done_testing;
