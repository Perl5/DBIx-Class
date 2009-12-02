#
#===============================================================================
#
#         FILE:  02admin..t
#
#  DESCRIPTION:  
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Gordon Irving (), <Gordon.irving@sophos.com>
#      COMPANY:  Sophos
#      VERSION:  1.0
#      CREATED:  28/11/09 16:14:21 GMT
#     REVISION:  ---
#===============================================================================

use strict;
use warnings;

use Test::More;                      # last test to print

use Test::Exception;

use Path::Class;
use FindBin qw($Bin);

use Module::Load;

use lib dir($Bin,'..', '..','lib')->stringify;
use lib dir($Bin,'..', 'lib')->stringify;

use ok 'DBIx::Class::Admin';

use DBICTest;

my $sql_dir = dir($Bin,"..","var");

{ # create the schema

#  make sure we are  clean
clean_dir($sql_dir);

# create a DBICTest so we can steal its connect info
my $schema = DBICTest->init_schema(
    no_deploy=>1,
    no_populate=>1,
	);


my $admin = DBIx::Class::Admin->new(
	schema_class=> "DBICTest::Schema",
	sql_dir=> $sql_dir,
	connect_info => $schema->storage->connect_info() 
);
isa_ok ($admin, 'DBIx::Class::Admin', 'create the admin object');
lives_ok { $admin->create('MySQL'); } 'Can create MySQL sql';
lives_ok { $admin->create('SQLite'); } 'Can Create SQLite sql';
}

{ # upgrade schema

my $schema = DBICTest->init_schema(
	no_deploy		=> 1,
	no_populat		=> 1,
	sqlite_use_file	=> 1,
);

clean_dir($sql_dir);
load 'DBICVersionOrig';

my $admin = DBIx::Class::Admin->new(
	schema_class => 'DBICVersion::Schema', 
	sql_dir =>  $sql_dir,
	connect_info => $schema->storage->connect_info(),
);
lives_ok { $admin->create($schema->storage->sqlt_type(), {add_drop_table=>0}); } 'Can create DBICVersionOrig sql in ' . $schema->storage->sqlt_type;
lives_ok { $admin->deploy(  ) } 'Can Deploy schema';

# connect to now deployed schema
lives_ok { $schema = DBICVersion::Schema->connect(@{$schema->storage->connect_info()}); } 'Connect to deployed Database';

is($schema->get_db_version, $DBICVersion::Schema::VERSION, 'Schema deployed and versions match');


load 'DBICVersionNew';

$admin = DBIx::Class::Admin->new(
	schema_class => 'DBICVersion::Schema', 
	sql_dir =>  "t/var",
	connect_info => $schema->storage->connect_info(),
);

$admin->preversion("1.0");
lives_ok { $admin->create($schema->storage->sqlt_type(), ); } 'Can create diff for ' . $schema->storage->sqlt_type;
lives_ok {$admin->upgrade();} 'upgrade the schema';

is($schema->get_db_version, $DBICVersion::Schema::VERSION, 'Schema and db versions match');

}

{ # install

clean_dir($sql_dir);

my $schema = DBICTest->init_schema(
    no_deploy=>1,
    no_populate=>1,
	sqlite_use_file	=> 1,
	);

my $admin = DBIx::Class::Admin->new(
	schema_class	=> 'DBICVersion::Schema', 
	sql_dir			=> $sql_dir,
	connect_info	=> $schema->storage->connect_info(),
	_confirm		=> 1,
);

$admin->version("3.0");
lives_ok { $admin->install(); } 'install schema version 3.0';
is($admin->schema->get_db_version, "3.0", 'db thinks its version 3.0');
dies_ok { $admin->install("4.0"); } 'cannot install to allready existing version';
sleep 1;
$admin->force(1);
lives_ok { $admin->install("4.0"); } 'can force install to allready existing version';
is($admin->schema->get_db_version, "4.0", 'db thinks its version 4.0');
#clean_dir($sql_dir);
}

sub clean_dir {
	my ($dir)  =@_;
	$dir = $dir->resolve;
	if ( ! -d $dir ) {
		$dir->mkpath();
	}
	foreach my $file ($dir->children) {
		# skip any hidden files
		next if ($file =~ /^\./); 
		unlink $file;
	}
}

done_testing;
