use strict;
use Module::Build;

my %arguments = (
    create_makefile_pl => 'passthrough',
    license            => 'perl',
    module_name        => 'DBIx::Class',
    requires           => {
        'DBI'           => 0,
        'NEXT'          => 0,
        'DBD::SQLite'   => 1.08
    },
    create_makefile_pl => 'passthrough',
    create_readme      => 1,
    test_files         => [ glob('t/*.t'), glob('t/*/*.t') ]
);

Module::Build->new(%arguments)->create_build_script;

