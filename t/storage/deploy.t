use strict;
use warnings;

use Test::More;
use Test::Exception;
use Path::Class qw/dir/;

use lib qw(t/lib);
use DBICTest;

BEGIN {
  require DBIx::Class;
  plan skip_all =>
      'Test needs ' . DBIx::Class::Optional::Dependencies->req_missing_for ('deploy')
    unless DBIx::Class::Optional::Dependencies->req_ok_for ('deploy')
}

local $ENV{DBI_DSN};

# this is how maint/gen_schema did it (connect() to force a storage
# instance, but no conninfo)
# there ought to be more code like this in the wild
like(
  DBICTest::Schema->connect->deployment_statements('SQLite'),
  qr/\bCREATE TABLE\b/i
);

lives_ok( sub {
    my $parse_schema = DBICTest->init_schema(no_deploy => 1);
    $parse_schema->deploy({},'t/lib/test_deploy');
    $parse_schema->resultset("Artist")->all();
}, 'artist table deployed correctly' );

my $schema = DBICTest->init_schema();

my $var = dir ("t/var/ddl_dir-$$");
$var->mkpath unless -d $var;

my $test_dir_1 = $var->subdir ('test1', 'foo', 'bar' );
$test_dir_1->rmtree if -d $test_dir_1;
$schema->create_ddl_dir( undef, undef, $test_dir_1 );

ok( -d $test_dir_1, 'create_ddl_dir did a make_path on its target dir' );
ok( scalar( glob $test_dir_1.'/*.sql' ), 'there are sql files in there' );

{
  local $TODO = 'we should probably add some tests here for actual deployability of the DDL?';
  ok( 0 );
}

END {
  $var->rmtree;
}

done_testing;
