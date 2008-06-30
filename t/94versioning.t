#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use File::Spec;
use File::Copy;

#warn "$dsn $user $pass";
my ($dsn, $user, $pass);

BEGIN {
  ($dsn, $user, $pass) = @ENV{map { "DBICTEST_MYSQL_${_}" } qw/DSN USER PASS/};

  plan skip_all => 'Set $ENV{DBICTEST_MYSQL_DSN}, _USER and _PASS to run this test'
    unless ($dsn);


    eval "use DBD::mysql; use SQL::Translator 0.09;";
    plan $@
        ? ( skip_all => 'needs DBD::mysql and SQL::Translator 0.09 for testing' )
        : ( tests => 13 );
}

my $version_table_name = 'dbix_class_schema_versions';
my $old_table_name = 'SchemaVersions';

use lib qw(t/lib);
use_ok('DBICVersionOrig');

my $schema_orig = DBICVersion::Schema->connect($dsn, $user, $pass);
eval { $schema_orig->storage->dbh->do('drop table ' . $version_table_name) };
eval { $schema_orig->storage->dbh->do('drop table ' . $old_table_name) };

is($schema_orig->ddl_filename('MySQL', 't/var', '1.0'), File::Spec->catfile('t', 'var', 'DBICVersion-Schema-1.0-MySQL.sql'), 'Filename creation working');
unlink('t/var/DBICVersion-Schema-1.0-MySQL.sql') if (-e 't/var/DBICVersion-Schema-1.0-MySQL.sql');
$schema_orig->create_ddl_dir('MySQL', undef, 't/var');

ok(-f 't/var/DBICVersion-Schema-1.0-MySQL.sql', 'Created DDL file');
$schema_orig->deploy({ add_drop_table => 1 });
$schema_orig->upgrade();

my $tvrs = $schema_orig->{vschema}->resultset('Table');
is($schema_orig->_source_exists($tvrs), 1, 'Created schema from DDL file');

eval "use DBICVersionNew";
{
  unlink('t/var/DBICVersion-Schema-2.0-MySQL.sql');
  unlink('t/var/DBICVersion-Schema-1.0-2.0-MySQL.sql');

  my $schema_upgrade = DBICVersion::Schema->connect($dsn, $user, $pass);
  is($schema_upgrade->get_db_version(), '1.0', 'get_db_version ok');
  is($schema_upgrade->schema_version, '2.0', 'schema version ok');
  $schema_upgrade->create_ddl_dir('MySQL', '2.0', 't/var', '1.0');
  ok(-f 't/var/DBICVersion-Schema-1.0-2.0-MySQL.sql', 'Created DDL file');
  $schema_upgrade->upgrade();
  is($schema_upgrade->get_db_version(), '2.0', 'db version number upgraded');

  eval {
    $schema_upgrade->storage->dbh->do('select NewVersionName from TestVersion');
  };
  is($@, '', 'new column created');
}

{
  my $schema_version = DBICVersion::Schema->connect($dsn, $user, $pass);
  eval {
    $schema_version->storage->dbh->do('select * from ' . $version_table_name);
  };
  is($@, '', 'version table exists');

  eval {
    $schema_version->storage->dbh->do("DROP TABLE IF EXISTS $old_table_name");
    $schema_version->storage->dbh->do("RENAME TABLE $version_table_name TO $old_table_name");
  };
  is($@, '', 'versions table renamed to old style table');

  $schema_version = DBICVersion::Schema->connect($dsn, $user, $pass);
  is($schema_version->get_db_version, '2.0', 'transition from old table name to new okay');

  eval {
    $schema_version->storage->dbh->do('select * from ' . $old_table_name);
  };
  ok($@, 'old version table gone');

}

# check behaviour of DBIC_NO_VERSION_CHECK env var and ignore_version connect attr
{
  my $schema_version = DBICVersion::Schema->connect($dsn, $user, $pass);
  eval {
    $schema_version->storage->dbh->do("DROP TABLE IF EXISTS $version_table_name");
  };

  $schema_version = DBICVersion::Schema->connect($dsn, $user, $pass);
  # should warn

  $schema_version = DBICVersion::Schema->connect($dsn, $user, $pass, { ignore_version => 1 });
  # should not warn

  $ENV{DBIC_NO_VERSION_CHECK} = 1;
  $schema_version = DBICVersion::Schema->connect($dsn, $user, $pass);
  # should not warn

  $schema_version = DBICVersion::Schema->connect($dsn, $user, $pass, { ignore_version => 0 });
  # should warn
}
