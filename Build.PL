use strict;
use Module::Build;

my %arguments = (
    create_makefile_pl => 'passthrough',
    license            => 'perl',
    module_name        => 'DBIx::Class',
    requires           => {
        'Data::Page'                => 0,
        'DBI'                       => 0,
        'UNIVERSAL::require'        => 0,
        'NEXT'                      => 0,
        'Scalar::Util'              => 0,
        'SQL::Abstract'             => 1.20,
        'SQL::Abstract::Limit'      => 0.101,
        'DBD::SQLite'               => 1.08,
	'Tie::IxHash'               => 0,
        'Storable'                  => 0,
        'Module::Find'              => 0,
    },
    create_makefile_pl => 'passthrough',
    create_readme      => 1,
    test_files         => [ glob('t/*.t'), glob('t/*/*.t') ]
);

Module::Build->new(%arguments)->create_build_script;

