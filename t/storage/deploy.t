use strict;
use warnings;

use Test::More;
use Test::Exception;

use lib qw(t/lib);
use DBICTest;

BEGIN {
  require DBIx::Class;
  plan skip_all =>
      'Test needs ' . DBIx::Class::Optional::Dependencies->req_missing_for ('deploy')
    unless DBIx::Class::Optional::Dependencies->req_ok_for ('deploy')
}

use File::Spec;
use Path::Class qw/dir/;
use File::Path qw/make_path remove_tree/;

lives_ok( sub {
    my $parse_schema = DBICTest->init_schema(no_deploy => 1);
    $parse_schema->deploy({},'t/lib/test_deploy');
    $parse_schema->resultset("Artist")->all();
}, 'artist table deployed correctly' );

my $schema = DBICTest->init_schema();

my $var = dir (qw| t var create_ddl_dir |);
-d $var
    or make_path( "$var" )
    or die "can't create $var: $!";

my $test_dir_1 = $var->subdir ('test1', 'foo', 'bar' );
remove_tree( "$test_dir_1" ) if -d $test_dir_1;
$schema->create_ddl_dir( undef, undef, $test_dir_1 );

ok( -d $test_dir_1, 'create_ddl_dir did a make_path on its target dir' );
ok( scalar( glob $test_dir_1.'/*.sql' ), 'there are sql files in there' );

TODO: {
    local $TODO = 'we should probably add some tests here for actual deployability of the DDL?';
    ok( 0 );
}

done_testing;
