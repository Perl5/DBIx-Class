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
    unless ($dsn && $user);


    eval "use DBD::mysql; use SQL::Translator 0.08;";
    plan $@
        ? ( skip_all => 'needs DBD::mysql and SQL::Translator 0.08 for testing' )
        : ( tests => 9 );
}

use lib qw(t/lib);

use_ok('DBICVersionOrig');

my $schema_orig = DBICVersion::Schema->connect($dsn, $user, $pass);
eval { $schema_orig->storage->dbh->do('drop table SchemaVersions') };

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
