use inc::Module::Install 0.89;
use strict;
use warnings;
use POSIX ();

use 5.006001; # delete this line if you want to send patches for earlier.

# ****** DO NOT ADD OPTIONAL DEPENDENCIES. EVER. --mst ******

name     'DBIx-Class';
perl_version '5.006001';
all_from 'lib/DBIx/Class.pm';


test_requires 'Test::Builder'       => '0.33';
test_requires 'Test::Deep'          => '0';
test_requires 'Test::Exception'     => '0';
test_requires 'Test::More'          => '0.92';
test_requires 'Test::Warn'          => '0.21';

test_requires 'File::Temp'          => '0.22';


# Core
requires 'List::Util'               => '0';
requires 'Scalar::Util'             => '0';
requires 'Storable'                 => '0';

# Perl 5.8.0 doesn't have utf8::is_utf8()
requires 'Encode'                   => '0' if ($] <= 5.008000);

# Dependencies (keep in alphabetical order)
requires 'Carp::Clan'               => '6.0';
requires 'Class::Accessor::Grouped' => '0.09000';
requires 'Class::C3::Componentised' => '1.0005';
requires 'Class::Inspector'         => '1.24';
requires 'Data::Page'               => '2.00';
requires 'DBD::SQLite'              => '1.25';
requires 'DBI'                      => '1.605';
requires 'JSON::Any'                => '1.18';
requires 'MRO::Compat'              => '0.09';
requires 'Module::Find'             => '0.06';
requires 'Path::Class'              => '0.16';
requires 'Scope::Guard'             => '0.03';
requires 'SQL::Abstract'            => '1.60';
requires 'SQL::Abstract::Limit'     => '0.13';
requires 'Sub::Name'                => '0.04';
requires 'Data::Dumper::Concise'    => '1.000';

my %replication_requires = (
  'Moose',                    => '0.87',
  'MooseX::AttributeHelpers'  => '0.21',
  'MooseX::Types',            => '0.16',
  'namespace::clean'          => '0.11',
  'Hash::Merge',              => '0.11',
);

#************************************************************************#
# Make *ABSOLUTELY SURE* that nothing on this list is a real require,    #
# since every module listed in %force_requires_if_author is deleted      #
# from the final META.yml (thus will never make it as a CPAN dependency) #
#************************************************************************#
my %force_requires_if_author = (
  %replication_requires,

  # when changing also adjust $DBIx::Class::Storage::DBI::minimum_sqlt_version
  'SQL::Translator'           => '0.11002',

#  'Module::Install::Pod::Inherit' => '0.01',

  # when changing also adjust version in t/02pod.t
  'Test::Pod'                 => '1.26',

  # when changing also adjust version in t/03podcoverage.t
  'Test::Pod::Coverage'       => '1.08',
  'Pod::Coverage'             => '0.20',

  # CDBI-compat related
  'DBIx::ContextualFetch'     => '0',
  'Class::DBI::Plugin::DeepAbstractSearch' => '0',
  'Class::Trigger'            => '0',
  'Time::Piece::MySQL'        => '0',
  'Clone'                     => '0',
  'Date::Simple'              => '3.03',

  # t/52cycle.t
  'Test::Memory::Cycle'       => '0',
  'Devel::Cycle'              => '1.10',

  # t/36datetime.t
  # t/60core.t
  'DateTime::Format::SQLite'  => '0',

  # t/96_is_deteministic_value.t
  'DateTime::Format::Strptime'=> '0',

  # database-dependent reqs
  #
  $ENV{DBICTEST_PG_DSN}
    ? (
      'Sys::SigAction' => '0',
      'DBD::Pg' => '2.009002',
      'DateTime::Format::Pg' => '0',
    ) : ()
  ,

  $ENV{DBICTEST_MYSQL_DSN}
    ? (
      'DateTime::Format::MySQL' => '0',
    ) : ()
  ,

  $ENV{DBICTEST_ORA_DSN}
    ? (
      'DateTime::Format::Oracle' => '0',
    ) : ()
  ,

  $ENV{DBICTEST_SYBASE_DSN}
    ? (
      'DateTime::Format::Sybase' => 0,
    ) : ()
  ,
);
#************************************************************************#
# Make ABSOLUTELY SURE that nothing on the list above is a real require, #
# since every module listed in %force_requires_if_author is deleted      #
# from the final META.yml (thus will never make it as a CPAN dependency) #
#************************************************************************#


install_script (qw|
    script/dbicadmin
|);

tests_recursive (qw|
    t
|);

resources 'IRC'         => 'irc://irc.perl.org/#dbix-class';
resources 'license'     => 'http://dev.perl.org/licenses/';
resources 'repository'  => 'http://dev.catalyst.perl.org/repos/bast/DBIx-Class/';
resources 'MailingList' => 'http://lists.scsys.co.uk/cgi-bin/mailman/listinfo/dbix-class';

no_index 'DBIx::Class::SQLAHacks';
no_index 'DBIx::Class::SQLAHacks::MSSQL';
no_index 'DBIx::Class::SQLAHacks::OracleJoins';
no_index 'DBIx::Class::Storage::DBI::AmbiguousGlob';
no_index 'DBIx::Class::Storage::DBIHacks';
no_index 'DBIx::Class::PK::Auto::DB2';
no_index 'DBIx::Class::PK::Auto::MSSQL';
no_index 'DBIx::Class::PK::Auto::MySQL';
no_index 'DBIx::Class::PK::Auto::Oracle';
no_index 'DBIx::Class::PK::Auto::Pg';
no_index 'DBIx::Class::PK::Auto::SQLite';

# re-build README and require extra modules for testing if we're in a checkout

if ($Module::Install::AUTHOR) {
  warn <<'EOW';
******************************************************************************
******************************************************************************
***                                                                        ***
*** AUTHOR MODE: all optional test dependencies converted to hard requires ***
***                                                                        ***
******************************************************************************
******************************************************************************

EOW

  foreach my $module (sort keys %force_requires_if_author) {
    build_requires ($module => $force_requires_if_author{$module});
  }

  print "Regenerating README\n";
  system('pod2text lib/DBIx/Class.pm > README');

  if (-f 'MANIFEST') {
    print "Removing MANIFEST\n";
    unlink 'MANIFEST';
  }

#  require Module::Install::Pod::Inherit;
#  PodInherit();
}

auto_install();

WriteAll();

# Re-write META.yml to _exclude_ all forced requires (we do not want to ship this)
if ($Module::Install::AUTHOR) {

  Meta->{values}{build_requires} = [ grep 
    { not exists $force_requires_if_author{$_->[0]} }
    ( @{Meta->{values}{build_requires}} )
  ];

  Meta->write;
}
