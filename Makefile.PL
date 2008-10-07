use inc::Module::Install 0.67;
use strict;
use warnings;

use 5.006001; # delete this line if you want to send patches for earlier.

name     'DBIx-Class';
perl_version '5.006001';
all_from 'lib/DBIx/Class.pm';

requires 'Data::Page'                => 2.00;
requires 'Scalar::Util'              => 0;
requires 'SQL::Abstract'             => 1.20;
requires 'SQL::Abstract::Limit'      => 0.101;
requires 'Class::C3'                 => 0.13;
requires 'Class::C3::Componentised'  => 0;
requires 'Storable'                  => 0;
requires 'Carp::Clan'                => 0;
requires 'DBI'                       => 1.40;
requires 'Module::Find'              => 0;
requires 'Class::Inspector'          => 0;
requires 'Class::Accessor::Grouped'  => 0.05002;
requires 'JSON::Any'                 => 1.00; 
requires 'Scope::Guard'              => 0.03;
requires 'Path::Class'               => 0;
requires 'List::Util'                => 1.19;
requires 'Sub::Name'                 => 0.04;

# Perl 5.8.0 doesn't have utf8::is_utf8()
requires 'Encode'                    => 0 if ($] <= 5.008000);  

test_requires 'DBD::SQLite'         => 1.13;
test_requires 'Test::Builder'       => 0.33;
test_requires 'Test::Warn'          => 0.11;
test_requires 'Test::NoWarnings'    => 0.08;
test_requires 'Test::Exception'     => 0;

install_script 'script/dbicadmin';

tests "t/*.t t/*/*.t";

# re-build README and require CDBI modules for testing if we're in a checkout

my @force_build_requires_if_author = qw(
  DBIx::ContextualFetch
  Class::Trigger
  Time::Piece
  Clone
  Test::Pod::Coverage
  Test::Memory::Cycle
);

if ($Module::Install::AUTHOR) {

  foreach my $module (@force_build_requires_if_author) {
    build_requires $module;
  }

  system('pod2text lib/DBIx/Class.pm > README');
}

auto_provides;

auto_install;

WriteAll;


if ($Module::Install::AUTHOR) {
  # Need to do this _after_ WriteAll else it looses track of them
  Meta->{values}{build_requires} = [ grep {
    my $ok = 1;
    foreach my $module (@force_build_requires_if_author) {
      if ($_->[0] =~ /$module/) {
        $ok = 0;
        last;
      }
    }
    $ok;
  } @{Meta->{values}{build_requires}} ];

  my @scalar_keys = Module::Install::Metadata::Meta_TupleKeys();
  my $cr = Module::Install::Metadata->can("Meta_TupleKeys");
  {
    no warnings 'redefine';
    *Module::Install::Metadata::Meta_TupleKeys = sub {
      return $cr->(@_), 'resources';
    };
  }
  Meta->{values}{resources} = [ 
    [ 'MailingList', 'http://lists.scsys.co.uk/cgi-bin/mailman/listinfo/dbix-class' ],
    [ 'IRC', 'irc://irc.perl.org/#dbix-class' ],
    [ 'license', 'http://dev.perl.org/licenses/' ],
    [ 'repository', 'http://dev.catalyst.perl.org/svnweb/bast/browse/DBIx-Class/' ],
  ];
  Meta->write;
}



