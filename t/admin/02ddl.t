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
use lib dir($Bin,'..', '..','lib')->stringify;
use lib dir($Bin,'..', 'lib')->stringify;

use ok 'DBIx::Class::Admin';

use DBICTest;

my $sql_dir = dir($Bin,"var","sql");


{ # create the schema

my $schema = DBICTest->init_schema(
    no_deploy=>1,
    no_populate=>1,
	);
	clean_dir($sql_dir);
my $admin = DBIx::Class::Admin->new(
	schema_class=> "DBICTest::Schema",
	sql_dir=> $sql_dir,
	connect_info => $schema->storage->connect_info() 
);

lives_ok { $admin->create('MySQL'); } 'Can create MySQL sql';
lives_ok { $admin->create('SQLite'); } 'Can Create SQLite sql';
}


{ # upgrade schema

my $schema = DBICTest->init_schema(
    no_deploy=>1,
    no_populate=>1,
	);

	clean_dir($sql_dir);
use DBICVersionOrig;

my $admin = DBIx::Class::Admin->new(
	schema_class => 'DBICVersion::Schema', 
	sql_dir =>  $sql_dir,
	connect_info => $schema->storage->connect_info(),
);
lives_ok { $admin->create($schema->storage->sqlt_type()); } 'Can create DBICVersionOrig sql in ' . $schema->storage->sqlt_type;
lives_ok { $admin->deploy(); } 'Can Deploy schema';

}

sub clean_dir {
	my ($dir)  =@_;
	foreach my $file ($dir->children) {
		unlink $file;
	}
}

done_testing;
