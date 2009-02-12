use inc::Module::Install 0.67;

name     'DBIx-Class';
perl_version '5.006001';
all_from 'lib/DBIx/Class.pm';

requires 'Data::Page'                => 2.00;
requires 'Scalar::Util'              => 0;
requires 'SQL::Abstract'             => 1.24;
requires 'SQL::Abstract::Limit'      => 0.13;
requires 'Class::C3'                 => 0.20;
requires 'Class::C3::Componentised'  => 0;
requires 'Storable'                  => 0;
requires 'Carp::Clan'                => 0;
requires 'DBI'                       => 1.40;
requires 'Module::Find'              => 0;
requires 'Class::Inspector'          => 0;
requires 'Class::Accessor::Grouped'  => 0.08002;
requires 'JSON::Any'                 => 1.17;
requires 'Scope::Guard'              => 0.03;
requires 'List::Util'                => 1.19;

# Perl 5.8.0 doesn't have utf8::is_utf8()
requires 'Encode'                    => 0 if ($] <= 5.008000);  

test_requires 'DBD::SQLite'         => 1.14;
test_requires 'Test::Builder'       => 0.33;
test_requires 'Test::Exception'     => 0;
test_requires 'Test::Deep'          => 0;

install_script 'script/dbicadmin';

tests "t/*.t t/*/*.t";

# re-build README and require CDBI modules for testing if we're in a checkout
if( -e 'inc/.author' ) {
  build_requires 'DBIx::ContextualFetch';
  build_requires 'Class::Trigger';
  system('pod2text lib/DBIx/Class.pm > README');
}

auto_provides;

auto_install;
# Have all prerequisites, check DBD::SQLite sanity
if (! $ENV{DBICTEST_NO_SQLITE_CHECK} ) {

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

  my $pid = fork();
  if (not defined $pid) {
      die "Unable to fork(): $!";
  }
  elsif (! $pid) {

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
      wait();
      my $sig = $? & 127;
      if ($sig == 11) {
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

WriteAll;
