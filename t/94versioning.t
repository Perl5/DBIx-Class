#!/usr/bin/perl
use strict;
use warnings;
use Test::More;

BEGIN {
    eval "use DBD::SQLite; use SQL::Translator;";
    plan $@
        ? ( skip_all => 'needs DBD::SQLite and SQL::Translator for testing' )
        : ( tests => 6 );
}

use lib qw(t/lib);

use_ok('DBICVersionOrig');

my $db_file = "t/var/versioning.db";
unlink($db_file) if -e $db_file;
unlink($db_file . "-journal") if -e $db_file . "-journal";
mkdir("t/var") unless -d "t/var";
unlink('t/var/DBICVersion-Schema-1.0-SQLite.sql');

my $schema = DBICVersion::Schema->connect("dbi:SQLite:$db_file");
# $schema->storage->ensure_connected();

is($schema->ddl_filename('SQLite', 't/var', '1.0'), 't/var/DBICVersion-Schema-1.0-SQLite.sql', 'Filename creation working');
$schema->create_ddl_dir('SQLite', undef, 't/var');

ok(-f 't/var/DBICVersion-Schema-1.0-SQLite.sql', 'Created DDL file');
## do this here or let Versioned.pm do it?
# $schema->deploy();

my $tvrs = $schema->resultset('Table');
is($schema->exists($tvrs), 1, 'Created schema from DDL file');

eval "use DBICVersionNew";
my $schema2 = DBICVersion::Schema->connect("dbi:SQLite:$db_file");

unlink('t/var/DBICVersion-Schema-2.0-SQLite.sql');
unlink('t/var/DBICVersion-Schema-1.0-2.0-SQLite.sql');
$schema2->create_ddl_dir('SQLite', undef, 't/var', '1.0');
ok(-f 't/var/DBICVersion-Schema-1.0-2.0-SQLite.sql', 'Created DDL upgrade file');

## do this here or let Versioned.pm do it?
$schema2->upgrade();
$tvrs = $schema2->resultset('Table');
is($schema2->exists($tvrs), 1, 'Upgraded schema from DDL file');
