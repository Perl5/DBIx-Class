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

my $ddl_dir = File::Spec->catdir ('t', 'var');
my $fn = {
    v1 => File::Spec->catfile($ddl_dir, 'DBICVersion-Schema-1.0-MySQL.sql'),
    v2 => File::Spec->catfile($ddl_dir, 'DBICVersion-Schema-2.0-MySQL.sql'),
    v3 => File::Spec->catfile($ddl_dir, 'DBICVersion-Schema-3.0-MySQL.sql'),
    trans_v12 => File::Spec->catfile($ddl_dir, 'DBICVersion-Schema-1.0-2.0-MySQL.sql'),
    trans_v23 => File::Spec->catfile($ddl_dir, 'DBICVersion-Schema-2.0-3.0-MySQL.sql'),
};

use lib qw(t/lib);
use DBICTest; # do not remove even though it is not used

use_ok('DBICVersion_v1');

my $schema_v1 = DBICVersion::Schema->connect($dsn, $user, $pass, { ignore_version => 1 });
eval { $schema_v1->storage->dbh->do('drop table ' . $version_table_name) };
eval { $schema_v1->storage->dbh->do('drop table ' . $old_table_name) };

is($schema_v1->ddl_filename('MySQL', '1.0', $ddl_dir), $fn->{v1}, 'Filename creation working');
unlink( $fn->{v1} ) if ( -e $fn->{v1} );
$schema_v1->create_ddl_dir('MySQL', undef, $ddl_dir);

ok(-f $fn->{v1}, 'Created DDL file');
$schema_v1->deploy({ add_drop_table => 1 });

my $tvrs = $schema_v1->{vschema}->resultset('Table');
is($schema_v1->_source_exists($tvrs), 1, 'Created schema from DDL file');

# loading a new module defining a new version of the same table
DBICVersion::Schema->_unregister_source ('Table');
eval "use DBICVersion_v2";

my $schema_v2 = DBICVersion::Schema->connect($dsn, $user, $pass, { ignore_version => 1 });
{
  unlink($fn->{v2});
  unlink($fn->{trans_v12});

  is($schema_v2->get_db_version(), '1.0', 'get_db_version ok');
  is($schema_v2->schema_version, '2.0', 'schema version ok');
  $schema_v2->create_ddl_dir('MySQL', '2.0', $ddl_dir, '1.0');
  ok(-f $fn->{trans_v12}, 'Created DDL file');

  {
    my $w;
    local $SIG{__WARN__} = sub { $w = shift };

    $schema_v2->upgrade();
    like ($w, qr/Attempting upgrade\.$/, 'Warn before upgrade');
  }

  is($schema_v2->get_db_version(), '2.0', 'db version number upgraded');

  eval {
    $schema_v2->storage->dbh->do('select NewVersionName from TestVersion');
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
  $schema_v2->create_ddl_dir('MySQL', '2.0', $ddl_dir, '1.0');

  is (2, @w, 'A warning generated for both the DDL and the diff');
  like ($w[0], qr/Overwriting existing DDL file - $fn->{v2}/, 'New version DDL overwrite warning');
  like ($w[1], qr/Overwriting existing diff file - $fn->{trans_v12}/, 'Upgrade diff overwrite warning');
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

# repeat the v1->v2 process for v2->v3 before testing v1->v3
DBICVersion::Schema->_unregister_source ('Table');
eval "use DBICVersion_v3";

my $schema_v3 = DBICVersion::Schema->connect($dsn, $user, $pass, { ignore_version => 1 });
{
  unlink($fn->{v3});
  unlink($fn->{trans_v23});

  is($schema_v3->get_db_version(), '2.0', 'get_db_version 2.0 ok');
  is($schema_v3->schema_version, '3.0', 'schema version 3.0 ok');
  $schema_v3->create_ddl_dir('MySQL', '3.0', $ddl_dir, '2.0');
  ok(-f $fn->{trans_v23}, 'Created DDL 2.0 -> 3.0 file');

  {
    my $w;
    local $SIG{__WARN__} = sub { $w = shift };

    $schema_v3->upgrade();
    like ($w, qr/Attempting upgrade\.$/, 'Warn before upgrade');
  }

  is($schema_v3->get_db_version(), '3.0', 'db version number upgraded');

  eval {
    $schema_v3->storage->dbh->do('select ExtraColumn from TestVersion');
  };
  is($@, '', 'new column created');
}

# now put the v1 schema back again
{
  # drop all the tables...
  eval { $schema_v1->storage->dbh->do('drop table ' . $version_table_name) };
  eval { $schema_v1->storage->dbh->do('drop table ' . $old_table_name) };
  eval { $schema_v1->storage->dbh->do('drop table TestVersion') };

  {
    local $DBICVersion::Schema::VERSION = '1.0';
    $schema_v1->deploy;
  }
  is($schema_v1->get_db_version(), '1.0', 'get_db_version 1.0 ok');
}

# attempt v1 -> v3 upgrade....
{
  {
    my $w;
    local $SIG{__WARN__} = sub { $w = shift };

    $schema_v3->upgrade();
    like ($w, qr/Attempting upgrade\.$/, 'Warn before upgrade');
  }

  is($schema_v3->get_db_version(), '3.0', 'db version number upgraded');
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

  eval { $schema_v2->storage->dbh->do('drop table ' . $version_table_name) };
  eval { $schema_v2->storage->dbh->do('drop table ' . $old_table_name) };
  eval { $schema_v2->storage->dbh->do('drop table TestVersion') };

  # this attempts to sleep until the turn of the second
  my $t = time();
  sleep (int ($t) + 1 - $t);
  diag ('Fast deploy/upgrade start: ', time() );

  {
    local $DBICVersion::Schema::VERSION = '2.0';
    $schema_v2->deploy;
  }

  local $SIG{__WARN__} = sub { warn if $_[0] !~ /Attempting upgrade\.$/ };
  $schema_v2->upgrade();

  is($schema_v2->get_db_version(), '3.0', 'Fast deploy/upgrade');
};

unless ($ENV{DBICTEST_KEEP_VERSIONING_DDL}) {
    unlink $_ for (values %$fn);
}

done_testing;
