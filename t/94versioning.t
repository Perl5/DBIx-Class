#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use Test::Warn;
use Test::Exception;

use Path::Class;
use File::Copy;

#warn "$dsn $user $pass";
my ($dsn, $user, $pass);

BEGIN {
  ($dsn, $user, $pass) = @ENV{map { "DBICTEST_MYSQL_${_}" } qw/DSN USER PASS/};

  plan skip_all => 'Set $ENV{DBICTEST_MYSQL_DSN}, _USER and _PASS to run this test'
    unless ($dsn);

  eval { require Time::HiRes }
    || plan skip_all => 'Test needs Time::HiRes';
  Time::HiRes->import(qw/time sleep/);

  require DBIx::Class::Storage::DBI;
  plan skip_all =>
      'Test needs SQL::Translator ' . DBIx::Class::Storage::DBI->_sqlt_minimum_version
    if not DBIx::Class::Storage::DBI->_sqlt_version_ok;
}

my $version_table_name = 'dbix_class_schema_versions';
my $old_table_name = 'SchemaVersions';

my $ddl_dir = dir ('t', 'var');
my $fn = {
    v1 => $ddl_dir->file ('DBICVersion-Schema-1.0-MySQL.sql'),
    v2 => $ddl_dir->file ('DBICVersion-Schema-2.0-MySQL.sql'),
    trans => $ddl_dir->file ('DBICVersion-Schema-1.0-2.0-MySQL.sql'),
};

use lib qw(t/lib);
use DBICTest; # do not remove even though it is not used

use_ok('DBICVersionOrig');

my $schema_orig = DBICVersion::Schema->connect($dsn, $user, $pass, { ignore_version => 1 });
eval { $schema_orig->storage->dbh->do('drop table ' . $version_table_name) };
eval { $schema_orig->storage->dbh->do('drop table ' . $old_table_name) };

is($schema_orig->ddl_filename('MySQL', '1.0', $ddl_dir), $fn->{v1}, 'Filename creation working');
unlink( $fn->{v1} ) if ( -e $fn->{v1} );
$schema_orig->create_ddl_dir('MySQL', undef, $ddl_dir);

ok(-f $fn->{v1}, 'Created DDL file');
$schema_orig->deploy({ add_drop_table => 1 });

my $tvrs = $schema_orig->{vschema}->resultset('Table');
is($schema_orig->_source_exists($tvrs), 1, 'Created schema from DDL file');

# loading a new module defining a new version of the same table
DBICVersion::Schema->_unregister_source ('Table');
eval "use DBICVersionNew";

my $schema_upgrade = DBICVersion::Schema->connect($dsn, $user, $pass, { ignore_version => 1 });
{
  unlink($fn->{v2});
  unlink($fn->{trans});

  is($schema_upgrade->get_db_version(), '1.0', 'get_db_version ok');
  is($schema_upgrade->schema_version, '2.0', 'schema version ok');
  $schema_upgrade->create_ddl_dir('MySQL', '2.0', $ddl_dir, '1.0');
  ok(-f $fn->{trans}, 'Created DDL file');

  sleep 1;    # remove this when TODO below is completed
  warnings_like (
    sub { $schema_upgrade->upgrade() },
    qr/DB version .+? is lower than the schema version/,
    'Warn before upgrade',
  );

  is($schema_upgrade->get_db_version(), '2.0', 'db version number upgraded');

  lives_ok ( sub {
    $schema_upgrade->storage->dbh->do('select NewVersionName from TestVersion');
  }, 'new column created' );

  warnings_exist (
    sub { $schema_upgrade->create_ddl_dir('MySQL', '2.0', $ddl_dir, '1.0') },
    [
      qr/Overwriting existing DDL file - $fn->{v2}/,
      qr/Overwriting existing diff file - $fn->{trans}/,
    ],
    'An overwrite warning generated for both the DDL and the diff',
  );
}

{
  my $schema_version = DBICVersion::Schema->connect($dsn, $user, $pass);
  lives_ok (sub {
    $schema_version->storage->dbh->do('select * from ' . $version_table_name);
  }, 'version table exists');

  lives_ok (sub {
    $schema_version->storage->dbh->do("DROP TABLE IF EXISTS $old_table_name");
    $schema_version->storage->dbh->do("RENAME TABLE $version_table_name TO $old_table_name");
  }, 'versions table renamed to old style table');

  $schema_version = DBICVersion::Schema->connect($dsn, $user, $pass);
  is($schema_version->get_db_version, '2.0', 'transition from old table name to new okay');

  dies_ok (sub {
    $schema_version->storage->dbh->do('select * from ' . $old_table_name);
  }, 'old version table gone');

}

# check behaviour of DBIC_NO_VERSION_CHECK env var and ignore_version connect attr
{
  my $schema_version = DBICVersion::Schema->connect($dsn, $user, $pass);
  eval {
    $schema_version->storage->dbh->do("DELETE from $version_table_name");
  };


  warnings_like ( sub {
    $schema_version = DBICVersion::Schema->connect($dsn, $user, $pass);
  }, qr/Your DB is currently unversioned/, 'warning detected without env var or attr' );

  warnings_like ( sub {
    $schema_version = DBICVersion::Schema->connect($dsn, $user, $pass, { ignore_version => 1 });
  },  [], 'warning not detected with attr set');


  local $ENV{DBIC_NO_VERSION_CHECK} = 1;
  warnings_like ( sub {
    $schema_version = DBICVersion::Schema->connect($dsn, $user, $pass);
  }, [], 'warning not detected with env var set');

  warnings_like ( sub {
    $schema_version = DBICVersion::Schema->connect($dsn, $user, $pass, { ignore_version => 0 });
  }, qr/Your DB is currently unversioned/, 'warning detected without env var or attr');
}

# attempt a deploy/upgrade cycle within one second
TODO: {

  local $TODO = 'To fix this properly the table must be extended with an autoinc column, mst will not accept anything less';

  eval { $schema_orig->storage->dbh->do('drop table ' . $version_table_name) };
  eval { $schema_orig->storage->dbh->do('drop table ' . $old_table_name) };
  eval { $schema_orig->storage->dbh->do('drop table TestVersion') };

  # this attempts to sleep until the turn of the second
  my $t = time();
  sleep (int ($t) + 1 - $t);
  diag ('Fast deploy/upgrade start: ', time() );

  {
    local $DBICVersion::Schema::VERSION = '1.0';
    $schema_orig->deploy;
  }

  local $SIG{__WARN__} = sub { warn if $_[0] !~ /Attempting upgrade\.$/ };
  $schema_upgrade->upgrade();

  is($schema_upgrade->get_db_version(), '2.0', 'Fast deploy/upgrade');
};

unless ($ENV{DBICTEST_KEEP_VERSIONING_DDL}) {
    unlink $_ for (values %$fn);
}

done_testing;
