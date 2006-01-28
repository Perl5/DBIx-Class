use strict;
use Module::Build;

my %arguments = (
    create_makefile_pl => 'passthrough',
    license            => 'perl',
    module_name        => 'DBIx::Class',
    requires           => {
        'Data::Page'                => 2.00,
        'DBI'                       => 1.40,
        'Scalar::Util'              => 0,
        'SQL::Abstract'             => 1.20,
        'SQL::Abstract::Limit'      => 0.101,
        'DBD::SQLite'               => 1.08,
        'Class::C3'                 => 0.07,
        'Tie::IxHash'               => 0,
        'Module::Find'              => 0,
        'Storable'                  => 0,
        'Class::Data::Accessor'     => 0.01,
	'Carp::Clan'		    => 0,
    },
    recommends          => {
        'Data::UUID'                => 0,
    },
    create_makefile_pl => 'passthrough',
    create_readme      => 1,
    test_files         => [ glob('t/*.t'), glob('t/*/*.t') ]
);

Module::Build->new(%arguments)->create_build_script;

