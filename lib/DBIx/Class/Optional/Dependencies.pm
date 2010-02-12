package DBIx::Class::Optional::Dependencies;

use warnings;
use strict;

# NO EXTERNAL DEPENDENCIES (e.g. C::A::G)
# This module is to be loaded by Makefile.PM on a pristine system

my $reqs = {
  dist => {
    #'Module::Install::Pod::Inherit' => '0.01',
  },

  replicated => {
    'Moose'                    => '0.98',
    'MooseX::Types'            => '0.21',
    'namespace::clean'          => '0.11',
    'Hash::Merge'              => '0.11',
  },

  admin => {
  },

  deploy => {
    'SQL::Translator'           => '0.11002',
  },

  author => {
    'Test::Pod'                 => '1.26',
    'Test::Pod::Coverage'       => '1.08',
    'Pod::Coverage'             => '0.20',
    #'Test::NoTabs'              => '0.9',
    #'Test::EOL'                 => '0.6',
  },

  core => {
    # t/52cycle.t
    'Test::Memory::Cycle'       => '0',
    'Devel::Cycle'              => '1.10',

    # t/36datetime.t
    # t/60core.t
    'DateTime::Format::SQLite'  => '0',

    # t/96_is_deteministic_value.t
    'DateTime::Format::Strptime'=> '0',
  },

  cdbicompat => {
    'DBIx::ContextualFetch'     => '0',
    'Class::DBI::Plugin::DeepAbstractSearch' => '0',
    'Class::Trigger'            => '0',
    'Time::Piece::MySQL'        => '0',
    'Clone'                     => '0',
    'Date::Simple'              => '3.03',
  },

  rdbms_pg => {
    $ENV{DBICTEST_PG_DSN}
      ? (
        'Sys::SigAction'        => '0',
        'DBD::Pg'               => '2.009002',
        'DateTime::Format::Pg'  => '0',
      ) : ()
  },

  rdbms_mysql => {
    $ENV{DBICTEST_MYSQL_DSN}
      ? (
        'DateTime::Format::MySQL' => '0',
        'DBD::mysql'              => '0',
      ) : ()
  },

  rdbms_oracle => {

    $ENV{DBICTEST_ORA_DSN}
      ? (
        'DateTime::Format::Oracle' => '0',
      ) : ()
  },

  rdbms_ase => {
    $ENV{DBICTEST_SYBASE_DSN}
      ? (
        'DateTime::Format::Sybase' => 0,
      ) : ()
  },

  rdbms_asa => {
    grep $_, @ENV{qw/DBICTEST_SYBASE_ASA_DSN DBICTEST_SYBASE_ASA_ODBC_DSN/}
      ? (
        'DateTime::Format::Strptime' => 0,
      ) : ()
  },
};

sub all_optional_requirements {
  return { map { %{ $_ || {} } } (values %$reqs) };
}

1;
