BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }
use DBIx::Class::Optional::Dependencies -skip_all_without => 'deploy';

use strict;
use warnings;

use Test::More;
use Test::Exception;

use DBICTest;
use DBICTest::Util qw( slurp_bytes rm_rf );
use DBIx::Class::_Util 'mkdir_p';

local $ENV{DBI_DSN};

# this is how maint/gen_schema did it (connect() to force a storage
# instance, but no conninfo)
# there ought to be more code like this in the wild
like(
  DBICTest::Schema->connect->deployment_statements('SQLite'),
  qr/\bCREATE TABLE artist\b/i  # ensure quoting *is* disabled
);

lives_ok( sub {
    my $parse_schema = DBICTest->init_schema(no_deploy => 1);
    $parse_schema->deploy({},'t/lib/test_deploy');
    $parse_schema->resultset("Artist")->all();
}, 'artist table deployed correctly' );

my $schema = DBICTest->init_schema( quote_names => 1 );

my $var_dir = "t/var/ddl_dir-$$/";
mkdir_p $var_dir unless -d $var_dir;

my $test_dir_1 = $var_dir . 'test1/foo/bar';
rm_rf $test_dir_1 if -d $test_dir_1;
$schema->create_ddl_dir( [qw(SQLite MySQL)], 1, $test_dir_1 );

ok( -d $test_dir_1, 'create_ddl_dir did a make_path on its target dir' );
ok( scalar( glob $test_dir_1.'/*.sql' ), 'there are sql files in there' );

my $less = $schema->clone;
$less->unregister_source('BindType');
$less->create_ddl_dir( [qw(SQLite MySQL)], 2, $test_dir_1, 1 );

for (
  [ SQLite => '"' ],
  [ MySQL => '`' ],
) {
  my $type = $_->[0];
  my $q = quotemeta($_->[1]);

  for my $f (map { $test_dir_1 . "/DBICTest-Schema-${_}-$type.sql" } qw(1 2) ) {
    like (
      scalar slurp_bytes $f,
      qr/CREATE TABLE ${q}track${q}/,
      "Proper quoting in $f"
    );
  }

  {
    local $TODO = 'SQLT::Producer::MySQL has no knowledge of the mythical beast of quoting...'
      if $type eq 'MySQL';

    my $f = $test_dir_1 . "/DBICTest-Schema-1-2-$type.sql";
    like (
      scalar slurp_bytes $f,
      qr/DROP TABLE ${q}bindtype_test${q}/,
      "Proper quoting in diff $f"
    );
  }
}

{
  local $TODO = 'we should probably add some tests here for actual deployability of the DDL?';
  ok( 0 );
}

END {
  rm_rf $var_dir;
}

done_testing;
