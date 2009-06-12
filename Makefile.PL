use inc::Module::Install 0.89;
use strict;
use warnings;
use POSIX ();

use 5.006001; # delete this line if you want to send patches for earlier.

name     'DBIx-Class';
perl_version '5.006001';
all_from 'lib/DBIx/Class.pm';

requires 'DBD::SQLite'              => 1.25;
requires 'Data::Page'               => 2.00;
requires 'SQL::Abstract'            => 1.56;
requires 'SQL::Abstract::Limit'     => 0.13;
requires 'Class::C3::Componentised' => 1.0005;
requires 'Carp::Clan'               => 6.0;
requires 'DBI'                      => 1.605;
requires 'Module::Find'             => 0.06;
requires 'Class::Inspector'         => 1.24;
requires 'Class::Accessor::Grouped' => 0.08003;
requires 'JSON::Any'                => 1.18;
requires 'Scope::Guard'             => 0.03;
requires 'Path::Class'              => 0.16;
requires 'Sub::Name'                => 0.04;
requires 'MRO::Compat'              => 0.09;

# Core
requires 'List::Util'               => 0;
requires 'Scalar::Util'             => 0;
requires 'Storable'                 => 0;

# Perl 5.8.0 doesn't have utf8::is_utf8()
requires 'Encode'                   => 0 if ($] <= 5.008000);

test_requires 'Test::More'          => 0.82;
test_requires 'Test::Builder'       => 0.33;
test_requires 'Test::Warn'          => 0.11;
test_requires 'Test::Exception'     => 0;
test_requires 'Test::Deep'          => 0;

recommends 'SQL::Translator'        => 0.09004;

install_script (qw|
    script/dbicadmin
|);

tests_recursive (qw|
    t
|);

resources 'IRC'         => 'irc://irc.perl.org/#dbix-class';
resources 'license'     => 'http://dev.perl.org/licenses/';
resources 'repository'  => 'http://dev.catalyst.perl.org/svnweb/bast/browse/DBIx-Class/';
resources 'MailingList' => 'http://lists.scsys.co.uk/cgi-bin/mailman/listinfo/dbix-class';


# re-build README and require extra modules for testing if we're in a checkout

my %force_requires_if_author = (
  'Test::Pod::Coverage'       => 1.04,
  'SQL::Translator'           => 0.09004,

  # CDBI-compat related
  'DBIx::ContextualFetch'     => 0,
  'Class::DBI::Plugin::DeepAbstractSearch' => 0,
  'Class::Trigger'            => 0,
  'Time::Piece::MySQL'        => 0,
  'Clone'                     => 0,
  'Date::Simple'              => 3.03,

  # t/52cycle.t
  'Test::Memory::Cycle'       => 0,
  'Devel::Cycle'              => 1.10,

  # t/inflate/datetime*.t
  # t/72.pg
  # t/36datetime.t
  # t/60core.t
  'DateTime::Format::SQLite'  => 0,
  'DateTime::Format::MySQL'   => 0,
  'DateTime::Format::Pg'      => 0,

  # t/96_is_deteministic_value.t
  'DateTime::Format::Strptime' => 0,

  # t/72pg.t
  $ENV{DBICTEST_PG_DSN}
    ? ('Sys::SigAction'=> 0)
    : ()
  ,

  # t/93storage_replication.t
  'Moose',                        => 0.77,
  'MooseX::AttributeHelpers'      => 0.12,
  'MooseX::Types',                => 0.10,
  'namespace::clean'              => 0.11,
  'Hash::Merge',                  => 0.11,

);

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

  foreach my $module (keys %force_requires_if_author) {
    build_requires ($module => $force_requires_if_author{$module});
  }

  print "Regenerating README\n";
  system('pod2text lib/DBIx/Class.pm > README');

  if (-f 'MANIFEST') {
    print "Removing MANIFEST\n";
    unlink 'MANIFEST';
  }
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
