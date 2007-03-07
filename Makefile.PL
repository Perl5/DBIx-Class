use inc::Module::Install 0.64;

name     'DBIx-Class';
all_from 'lib/DBIx/Class.pm';
perl_version '5.006001';

requires 'Cwd'                       => 3.19; 
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
requires 'Class::Accessor::Grouped'  => 0.03;
requires 'JSON'                      => 1.00; 

# Perl 5.8.0 doesn't have utf8::is_utf8()
requires 'Encode'                    => 0 if ($] <= 5.008000);  

build_requires 'DBD::SQLite'         => 1.11;

install_script 'script/dbicadmin';

tests "t/*.t t/*/*.t";

auto_install;

WriteAll;
