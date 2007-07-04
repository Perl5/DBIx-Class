use inc::Module::Install 0.67;

name     'DBIx-Class';
perl_version '5.006001';
all_from 'lib/DBIx/Class.pm';

requires 'Data::Page'                => 2.00;
requires 'Scalar::Util'              => 0;
requires 'SQL::Abstract'             => 1.20;
requires 'SQL::Abstract::Limit'      => 0.101;
requires 'Class::C3'                 => 0.13;
requires 'Storable'                  => 0;
requires 'Carp::Clan'                => 0;
requires 'DBI'                       => 1.40;
requires 'Module::Find'              => 0;
requires 'Class::Inspector'          => 0;
requires 'Class::Accessor::Grouped'  => 0.05002;
requires 'JSON'                      => 1.00; 
requires 'Scope::Guard'              => 0.03;

# Perl 5.8.0 doesn't have utf8::is_utf8()
requires 'Encode'                    => 0 if ($] <= 5.008000);  

build_requires 'DBD::SQLite'         => 1.11;

install_script 'script/dbicadmin';

tests "t/*.t t/*/*.t";

# re-build README if we're in an svk checkout
if( -e 'MANIFEST.SKIP' ) {
    system('pod2text lib/DBIx/Class.pm > README');
}

auto_provides;

auto_install;

WriteAll;
