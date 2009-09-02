#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Spec;
use File::Copy;
use Time::HiRes qw/time sleep/;

#warn "$dsn $user $pass";
my ($dsn, $user, $pass);

BEGIN {
  ($dsn, $user, $pass) = @ENV{map { "DBICTEST_MYSQL_${_}" } qw/DSN USER PASS/};

  plan skip_all => 'Set $ENV{DBICTEST_MYSQL_DSN}, _USER and _PASS to run this test'
    unless ($dsn);

  require DBIx::Class;
  plan skip_all =>
      'Test needs SQL::Translator ' . DBIx::Class->_sqlt_minimum_version
    if not DBIx::Class->_sqlt_version_ok;
}

my $version_table_name = 'dbix_class_schema_versions';
my $old_table_name = 'SchemaVersions';

my $ddl_dir = File::Spec->catdir ('t', 'var');
my $fn = {
    v1 => File::Spec->catfile($ddl_dir, 'DBICVersion-Schema-1.0-MySQL.sql'),
    v2 => File::Spec->catfile($ddl_dir, 'DBICVersion-Schema-2.0-MySQL.sql'),
    trans => File::Spec->catfile($ddl_dir, 'DBICVersion-Schema-1.0-2.0-MySQL.sql'),
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

  {
    my $w;
    local $SIG{__WARN__} = sub { $w = shift };

    sleep 1;    # remove this when TODO below is completed

    $schema_upgrade->upgrade();
    like ($w, qr/Attempting upgrade\.$/, 'Warn before upgrade');
  }

  is($schema_upgrade->get_db_version(), '2.0', 'db version number upgraded');

  eval {
    $schema_upgrade->storage->dbh->do('select NewVersionName from TestVersion');
  };
  is($@, '', 'new column created');

  # should overwrite files and warn about it
  my @w;
  local $SIG{__WARN__} = sub { 
    if ($_[0] =~ /Overwriting existing/) {
      push @w, $_[0];
    }
    else {
      warn @_;
    }
  };
  $schema_upgrade->create_ddl_dir('MySQL', '2.0', $ddl_dir, '1.0');

  is (2, @w, 'A warning generated for both the DDL and the diff');
  like ($w[0], qr/Overwriting existing DDL file - $fn->{v2}/, 'New version DDL overwrite warning');
  like ($w[1], qr/Overwriting existing diff file - $fn->{trans}/, 'Upgrade diff overwrite warning');
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
    $schema_version->storage->dbh->do("DELETE from $version_table_name");
  };


  my $warn = '';
  local $SIG{__WARN__} = sub { $warn = shift };
  $schema_version = DBICVersion::Schema->connect($dsn, $user, $pass);
  like($warn, qr/Your DB is currently unversioned/, 'warning detected without env var or attr');


  # should warn
  $warn = '';
  $schema_version = DBICVersion::Schema->connect($dsn, $user, $pass, { ignore_version => 1 });
  is($warn, '', 'warning not detected with attr set');
  # should not warn

  local $ENV{DBIC_NO_VERSION_CHECK} = 1;
  $warn = '';
  $schema_version = DBICVersion::Schema->connect($dsn, $user, $pass);
  is($warn, '', 'warning not detected with env var set');
  # should not warn

  $warn = '';
  $schema_version = DBICVersion::Schema->connect($dsn, $user, $pass, { ignore_version => 0 });
  like($warn, qr/Your DB is currently unversioned/, 'warning detected without env var or attr');
  # should warn
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
