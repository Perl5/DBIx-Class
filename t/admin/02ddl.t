# vim: et ts=2
#===============================================================================
#
#         FILE:  02admin..t
#
#  DESCRIPTION:  
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Gordon Irving (), <goraxe@cpan.org>
#      VERSION:  1.0
#      CREATED:  28/11/09 16:14:21 GMT
#     REVISION:  ---
#===============================================================================

use strict;
use warnings;

use Test::More;                      # last test to print

use Test::Exception;


BEGIN {
    use FindBin qw($Bin);
    use File::Spec::Functions qw(catdir);
    use lib catdir($Bin,'..', '..','lib');
    use lib catdir($Bin,'..', 'lib');

    eval "use DBIx::Class::Admin";
    plan skip_all => "Deps not installed: $@" if $@;
}

use Path::Class;

use ok 'DBIx::Class::Admin';

use DBICTest;

my $sql_dir = dir($Bin,"..","var");
my @connect_info = DBICTest->_database(
    no_deploy=>1,
    no_populate=>1,
    sqlite_use_file	=> 1,
);
{ # create the schema

#  make sure we are  clean
    clean_dir($sql_dir);


    my $admin = DBIx::Class::Admin->new(
        schema_class=> "DBICTest::Schema",
        sql_dir=> $sql_dir,
        connect_info => \@connect_info, 
    );
    isa_ok ($admin, 'DBIx::Class::Admin', 'create the admin object');
    lives_ok { $admin->create('MySQL'); } 'Can create MySQL sql';
    lives_ok { $admin->create('SQLite'); } 'Can Create SQLite sql';
}

{ # upgrade schema

#my $schema = DBICTest->init_schema(
#	no_deploy		=> 1,
#	no_populat		=> 1,
#	sqlite_use_file	=> 1,
#);

    clean_dir($sql_dir);
    require DBICVersionOrig;

    my $admin = DBIx::Class::Admin->new(
        schema_class => 'DBICVersion::Schema', 
        sql_dir =>  $sql_dir,
        connect_info => \@connect_info,
    );

    my $schema = $admin->schema();

    lives_ok { $admin->create($schema->storage->sqlt_type(), {add_drop_table=>0}); } 'Can create DBICVersionOrig sql in ' . $schema->storage->sqlt_type;
    lives_ok { $admin->deploy(  ) } 'Can Deploy schema';

# connect to now deployed schema
    lives_ok { $schema = DBICVersion::Schema->connect(@{$schema->storage->connect_info()}); } 'Connect to deployed Database';

    is($schema->get_db_version, $DBICVersion::Schema::VERSION, 'Schema deployed and versions match');


    require DBICVersionNew;

    $admin = DBIx::Class::Admin->new(
        schema_class => 'DBICVersion::Schema', 
        sql_dir =>  "t/var",
        connect_info => \@connect_info
    );

    lives_ok { $admin->create($schema->storage->sqlt_type(), {}, "1.0" ); } 'Can create diff for ' . $schema->storage->sqlt_type;
# sleep required for upgrade table to hold a distinct time of upgrade value
# otherwise the returned of get_db_version can be undeterministic
    sleep 1;
    lives_ok {$admin->upgrade();} 'upgrade the schema';

    is($schema->get_db_version, $DBICVersion::Schema::VERSION, 'Schema and db versions match');

}

{ # install

    clean_dir($sql_dir);

    my $admin = DBIx::Class::Admin->new(
        schema_class	=> 'DBICVersion::Schema', 
        sql_dir			=> $sql_dir,
        _confirm		=> 1,
        connect_info	=> \@connect_info,
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
