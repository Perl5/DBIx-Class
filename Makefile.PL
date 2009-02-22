use inc::Module::Install 0.67;
use strict;
use warnings;
use POSIX ();

use 5.006001; # delete this line if you want to send patches for earlier.

name     'DBIx-Class';
perl_version '5.006001';
all_from 'lib/DBIx/Class.pm';

requires 'Data::Page'               => 2.00;
requires 'Scalar::Util'             => 0;
requires 'SQL::Abstract'            => 1.49;
requires 'SQL::Abstract::Limit'     => 0.13;
requires 'Class::C3'                => 0.20;
requires 'Class::C3::Componentised' => 0;
requires 'Storable'                 => 0;
requires 'Carp::Clan'               => 0;
requires 'DBI'                      => 1.40;
requires 'Module::Find'             => 0;
requires 'Class::Inspector'         => 0;
requires 'Class::Accessor::Grouped' => 0.08002;
requires 'JSON::Any'                => 1.17;
requires 'Scope::Guard'             => 0.03;
requires 'Path::Class'              => 0;
requires 'List::Util'               => 1.19;
requires 'Sub::Name'                => 0.04;
requires 'namespace::clean'         => 0.09;

# Perl 5.8.0 doesn't have utf8::is_utf8()
requires 'Encode'                   => 0 if ($] <= 5.008000);  

configure_requires 'DBD::SQLite'    => 1.14;

test_requires 'Test::Builder'       => 0.33;
test_requires 'Test::Warn'          => 0.11;
test_requires 'Test::Exception'     => 0;
test_requires 'Test::Deep'          => 0;

recommends 'SQL::Translator'        => 0.09004;

install_script 'script/dbicadmin';

tests_recursive 't';

# re-build README and require CDBI modules for testing if we're in a checkout

my %force_requires_if_author = (
  'DBIx::ContextualFetch'     => 0,
  'Class::Trigger'            => 0,
  'Time::Piece'               => 0,
  'Clone'                     => 0,
  'Test::Pod::Coverage'       => 0,
  'Test::Memory::Cycle'       => 0,
  'SQL::Translator'           => 0.09004,
);

if ($Module::Install::AUTHOR) {

  foreach my $module (keys %force_requires_if_author) {
    requires ($module => $force_requires_if_author{$module});
  }

  system('pod2text lib/DBIx/Class.pm > README');
}

auto_provides;

auto_install;

# Have all prerequisites, check DBD::SQLite sanity
if (! $ENV{DBICTEST_NO_SQLITE_CHECK} ) {

  my $pid = fork();
  if (not defined $pid) {
      die "Unable to fork(): $!";
  }
  elsif (! $pid) {

      # Win32 does not have real fork()s so a segfault will bring
      # everything down. Warn about it.
      if ($^O eq 'MSWin32') {
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
      }

      require DBI;
      for (1 .. 100) {
          my $dbh;
          $dbh = DBI->connect ('dbi:SQLite::memory:', undef, undef, {
              AutoCommit => 1,
              RaiseError => 0,
              PrintError => 0,
          })
              or die "Unable to connect to database: $@";
          $dbh->do ('CREATE TABLE name_with_no_columns');   # a subtle syntax error
          $dbh->do ('COMMIT');                              # followed by commit
          $dbh->disconnect;
      }

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


WriteAll();


if ($Module::Install::AUTHOR) {
  # Need to do this _after_ WriteAll else it looses track of them
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
