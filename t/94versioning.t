BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }
use DBIx::Class::Optional::Dependencies -skip_all_without => qw(deploy test_rdbms_mysql);

use strict;
use warnings;

use Test::More;
use Test::Warn;
use Test::Exception;

use Time::HiRes qw/time sleep/;

use DBICTest;
use DBIx::Class::_Util qw( sigwarn_silencer mkdir_p );
use DBICTest::Util 'rm_rf';

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_MYSQL_${_}" } qw/DSN USER PASS/};

# this is just to grab a lock
{
  my $s = DBICTest::Schema->connect($dsn, $user, $pass);
}

# in case it came from the env
$ENV{DBIC_NO_VERSION_CHECK} = 0;

# FIXME - work around RT#113965 in combination with -T on older perls:
# the non-deparsing XS portion of D::D gets confused by some of the IO
# handles trapped in the debug object of DBIC. What a mess.
$Data::Dumper::Deparse = 1;

use_ok('DBICVersion_v1');

my $version_table_name = 'dbix_class_schema_versions';
my $old_table_name = 'SchemaVersions';

my $ddl_dir = "t/var/versioning_ddl-$$";
mkdir_p $ddl_dir unless -d $ddl_dir;

my $fn = {
    v1 => "$ddl_dir/DBICVersion-Schema-1.0-MySQL.sql",
    v2 => "$ddl_dir/DBICVersion-Schema-2.0-MySQL.sql",
    v3 => "$ddl_dir/DBICVersion-Schema-3.0-MySQL.sql",
    trans_v12 => "$ddl_dir/DBICVersion-Schema-1.0-2.0-MySQL.sql",
    trans_v23 => "$ddl_dir/DBICVersion-Schema-2.0-3.0-MySQL.sql",
};

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
use_ok('DBICVersion_v2');

my $schema_v2 = DBICVersion::Schema->connect($dsn, $user, $pass, { ignore_version => 1 });
{
  unlink($fn->{v2});
  unlink($fn->{trans_v12});

  is($schema_v2->get_db_version(), '1.0', 'get_db_version ok');
  is($schema_v2->schema_version, '2.0', 'schema version ok');
  $schema_v2->create_ddl_dir('MySQL', '2.0', $ddl_dir, '1.0');
  ok(-f $fn->{trans_v12}, 'Created DDL file');

  warnings_like (
    sub { $schema_v2->upgrade() },
    qr/DB version .+? is lower than the schema version/,
    'Warn before upgrade',
  );

  is($schema_v2->get_db_version(), '2.0', 'db version number upgraded');

  lives_ok ( sub {
    $schema_v2->storage->dbh->do('select NewVersionName from TestVersion');
  }, 'new column created' );

  warnings_exist (
    sub { $schema_v2->create_ddl_dir('MySQL', '2.0', $ddl_dir, '1.0') },
    [
      qr/Overwriting existing DDL file - \Q$fn->{v2}\E/,
      qr/Overwriting existing diff file - \Q$fn->{trans_v12}\E/,
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

# repeat the v1->v2 process for v2->v3 before testing v1->v3
DBICVersion::Schema->_unregister_source ('Table');
use_ok('DBICVersion_v3');

my $schema_v3 = DBICVersion::Schema->connect($dsn, $user, $pass, { ignore_version => 1 });
{
  unlink($fn->{v3});
  unlink($fn->{trans_v23});

  is($schema_v3->get_db_version(), '2.0', 'get_db_version 2.0 ok');
  is($schema_v3->schema_version, '3.0', 'schema version 3.0 ok');
  $schema_v3->create_ddl_dir('MySQL', '3.0', $ddl_dir, '2.0');
  ok(-f $fn->{trans_v23}, 'Created DDL 2.0 -> 3.0 file');

  warnings_exist (
    sub { $schema_v3->upgrade() },
    qr/DB version .+? is lower than the schema version/,
    'Warn before upgrade',
  );

  is($schema_v3->get_db_version(), '3.0', 'db version number upgraded');

  lives_ok ( sub {
    $schema_v3->storage->dbh->do('select ExtraColumn from TestVersion');
  }, 'new column created');
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

# attempt v1 -> v3 upgrade
{
  local $SIG{__WARN__} = sigwarn_silencer( qr/Attempting upgrade\.$/ );
  $schema_v3->upgrade();
  is($schema_v3->get_db_version(), '3.0', 'db version number upgraded');
}

# Now, try a v1 -> v3 upgrade with a file that has comments strategically placed in it.
# First put the v1 schema back again...
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

# add a "harmless" comment before one of the statements.
{
  my ($perl) = $^X =~ /(.+)/;
  local $ENV{PATH};
  system( qq($perl -pi.bak -e "s/ALTER/-- this is a comment\nALTER/" $fn->{trans_v23}) );
}

# Then attempt v1 -> v3 upgrade
{
  local $SIG{__WARN__} = sigwarn_silencer( qr/Attempting upgrade\.$/ );
  $schema_v3->upgrade();
  is($schema_v3->get_db_version(), '3.0', 'db version number upgraded to 3.0');

  # make sure that the column added after the comment is actually added.
  lives_ok ( sub {
    $schema_v3->storage->dbh->do('select ExtraColumn from TestVersion');
  }, 'new column created');
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
{
  eval { $schema_v2->storage->dbh->do('drop table ' . $version_table_name) };
  eval { $schema_v2->storage->dbh->do('drop table ' . $old_table_name) };
  eval { $schema_v2->storage->dbh->do('drop table TestVersion') };

  # this attempts to sleep until the turn of the second
  my $t = time();
  sleep (int ($t) + 1 - $t);
  note ('Fast deploy/upgrade start: ', time() );

  {
    local $DBICVersion::Schema::VERSION = '2.0';
    $schema_v2->deploy;
  }

  local $SIG{__WARN__} = sigwarn_silencer( qr/Attempting upgrade\.$/ );

  $schema_v2->upgrade();

  is($schema_v2->get_db_version(), '3.0', 'Fast deploy/upgrade');
};

# Check that it Schema::Versioned deals with new/all forms of connect arguments.
{
  my $get_db_version_run = 0;

  no warnings qw/once redefine/;
  local *DBIx::Class::Schema::Versioned::get_db_version = sub {
    $get_db_version_run = 1;
    return $_[0]->schema_version;
  };

  # Make sure the env var isn't whats triggering it
  local $ENV{DBIC_NO_VERSION_CHECK} = 0;

  DBICVersion::Schema->connect({
    dsn => $dsn,
    user => $user,
    pass => $pass,
    ignore_version => 1
  });

  ok($get_db_version_run == 0, "attributes pulled from hashref connect_info");
  $get_db_version_run = 0;

  DBICVersion::Schema->connect( $dsn, $user, $pass, { ignore_version => 1 } );
  ok($get_db_version_run == 0, "attributes pulled from list connect_info");
}

# at this point we have v1, v2 and v3 still connected
# make sure they are the only connections and everything else is gone
is
  scalar( grep
    { defined $_ and $_->{Active} }
    map
      { @{$_->{ChildHandles}} }
      values %{ { DBI->installed_drivers } }
  ), 3, "Expected number of connections at end of script"
;

# Test custom HandleError setting on an in-memory instance
{
  my $custom_handler = sub { die $_[0] };

  # try to setup a custom error handle without unsafe set -- should
  # fail, same behavior as regular Schema
  throws_ok {
    DBICVersion::Schema->connect( 'dbi:SQLite::memory:', undef, undef, {
      HandleError => $custom_handler,
      ignore_version => 1,
    })->deploy;
  }
    qr/Refusing clobbering of \{HandleError\} installed on externally supplied DBI handle/,
    'HandleError with unsafe not set causes an exception'
  ;

  # now try it with unsafe set -- should work (see RT #113741)
  my $s = DBICVersion::Schema->connect( 'dbi:SQLite::memory:', undef, undef, {
    unsafe => 1,
    HandleError => $custom_handler,
    ignore_version => 1,
  });

  $s->deploy;

  is $s->storage->dbh->{HandleError}, $custom_handler, 'Handler properly set on main schema';
  is $s->{vschema}->storage->dbh->{HandleError}, $custom_handler, 'Handler properly set on version subschema';
}

END {
  rm_rf $ddl_dir unless $ENV{DBICTEST_KEEP_VERSIONING_DDL};
}

done_testing;
