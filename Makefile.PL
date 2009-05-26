use inc::Module::Install 0.79;
use strict;
use warnings;
use POSIX ();

use 5.006001; # delete this line if you want to send patches for earlier.

name     'DBIx-Class';
perl_version '5.006001';
all_from 'lib/DBIx/Class.pm';

# configure_requires so _check_sqlite() below can run
# remove once test deprecated
configure_requires 'DBD::SQLite';

requires 'DBD::SQLite'              => 1.25;
requires 'Data::Page'               => 2.00;
requires 'SQL::Abstract'            => 1.55;
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
  'Date::Simple'              => 0,

  # t/52cycle.t
  'Test::Memory::Cycle'       => 0,

  # t/60core.t
  'DateTime::Format::MySQL'   => 0,
  
  # t/89inflate_datetime.t
  'DateTime::Format::Pg'      => 0,

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

  # t/96_is_deteministic_value.t
  'DateTime::Format::Strptime' => 0,
);

if ($Module::Install::AUTHOR) {

  foreach my $module (keys %force_requires_if_author) {
    build_requires ($module => $force_requires_if_author{$module});
  }

  system('pod2text lib/DBIx/Class.pm > README');
}

auto_provides;

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
}
auto_install;

# Have all prerequisites, check DBD::SQLite sanity
_check_sqlite() if (! $ENV{DBICTEST_NO_SQLITE_CHECK} );

WriteAll();

if ($Module::Install::AUTHOR) {
  # Need to do this _after_ WriteAll else it loses track of them
  Meta->{values}{build_requires} = [ grep {
    my $ok = 1;
    foreach my $module (keys %force_requires_if_author) {
      if ($_->[0] =~ /$module/) {
        $ok = 0;
        last;
      }
    }
    $ok;
  } @{Meta->{values}{build_requires}} ];

  Meta->{values}{resources} = [ 
    [ 'MailingList', 'http://lists.scsys.co.uk/cgi-bin/mailman/listinfo/dbix-class' ],
    [ 'IRC', 'irc://irc.perl.org/#dbix-class' ],
    [ 'license', 'http://dev.perl.org/licenses/' ],
    [ 'repository', 'http://dev.catalyst.perl.org/svnweb/bast/browse/DBIx-Class/' ],
  ];
  Meta->write;
}


# This is legacy code. Latest DBD::SQLite developments fixed all known bugs
# in this area. Remove before some arbitrary next version
sub _check_sqlite {

  # Win32 does not have real fork()s so a segfault will bring
  # everything down. Warn about it below, and don't try fork()
  if ($^O ne 'MSWin32') {

    my $pid = fork();
    if (not defined $pid) {
        die "Unable to fork(): $!";
    }
    elsif (! $pid) {
      _torture_sqlite();
      exit 0;
    }
    else {
      eval {
          local $SIG{ALRM} = sub { die "timeout\n" };
          alarm 5;
          wait();
          alarm 0;
      };
      my $exception = $@;

      my $sig = $? & 127;

      # make sure process actually dies
      $exception && kill POSIX::SIGKILL(), $pid;

      if ($exception || $sig == POSIX::SIGSEGV() || $sig == POSIX::SIGABRT()
        || $sig == 7) { # 7 == SIGBUS, haven't seen it but just in case
          warn (<<EOE);

############################### WARNING #################################
#                                                                       #
# You are running a buggy version of DBD::SQLite known to randomly      #
# segfault on errors.  Even if you have the latest CPAN module version, #
# the sqlite3 dynamic library on this system might have been compiled   #
# against an older buggy sqlite3 dev library (oddly DBD::SQLite will    #
# prefer the system library against the one bundled with it). You are   #
# strongly advised to resolve this issue before proceeding.             #
#                                                                       #
#########################################################################

EOE
          my $ans = prompt (
            "The test suite of this module is almost certain to fail.\n"
            . 'Do you really want to continue?',
            'no',
          );

          exit 0 unless ($ans =~ /^y(es)?$/i);
      }
    }
  }

  else {  # the win32 version

    print <<'EOW';
######################################################################
#                                                                    #
# A short stress-testing of DBD::SQLite will follow. If you have a   #
# buggy library this might very well be the last text you will see   #
# before the installation silently terminates. If this happens it    #
# would mean that you are running a buggy version of DBD::SQLite     #
# known to randomly segfault on errors. Even if you have the latest  #
# CPAN module version, the system sqlite3 dynamic library might have #
# been compiled against an older buggy sqlite3 dev library (oddly    #
# DBD::SQLite will prefer the system library against the one bundled #
# with it). You are strongly advised to resolve this issue before    #
# proceeding.                                                        #
#                                                                    #
# If this happens to you (this text is the last thing you see), and  #
# you just want to install this module without worrying about the    #
# tests (which will almost certainly fail) - set the environment     #
# variable DBICTEST_NO_SQLITE_CHECK to a true value and try again.   #
#                                                                    #
######################################################################

EOW

    _torture_sqlite();
  }
}

sub _torture_sqlite {
  require DBI;

  for (1 .. 100) {
    my $dbh = DBI->connect ('dbi:SQLite::memory:', undef, undef, {
      AutoCommit => 1,
      RaiseError => 0,
      PrintError => 0,
    }) or die "Unable to connect to database: $@";

    $dbh->do ('CREATE TABLE name_with_no_columns');   # a subtle syntax error
    $dbh->do ('COMMIT');                              # followed by commit
    $dbh->disconnect;
  }
}
