package # hide from PAUSE
    DBICTest::RunMode;

use strict;
use warnings;

use Path::Class qw/file dir/;
use Fcntl ':DEFAULT';
use File::Spec ();
use File::Temp ();
use DBICTest::Util qw( local_umask find_co_root );

# Try to determine the root of a checkout/untar if possible
# return a Path::Class::Dir object or undef
sub _find_co_root { eval { dir( find_co_root() ) } }

_check_author_makefile() unless $ENV{DBICTEST_NO_MAKEFILE_VERIFICATION};

# PathTools has a bug where on MSWin32 it will often return / as a tmpdir.
# This is *really* stupid and the result of having our lockfiles all over
# the place is also rather obnoxious. So we use our own heuristics instead
# https://rt.cpan.org/Ticket/Display.html?id=76663
my $tmpdir;
sub tmpdir {
  dir ($tmpdir ||= do {

    # works but not always
    my $dir = dir(File::Spec->tmpdir);
    my $reason_dir_unusable;

    my @parts = File::Spec->splitdir($dir);
    if (@parts == 2 and $parts[1] =~ /^ [\/\\]? $/x ) {
      $reason_dir_unusable =
        'File::Spec->tmpdir returned a root directory instead of a designated '
      . 'tempdir (possibly https://rt.cpan.org/Ticket/Display.html?id=76663)';
    }
    else {
      # make sure we can actually create and sysopen a file in this dir
      local $@;
      my $u = local_umask(0); # match the umask we use in DBICTest(::Schema)
      my $tempfile = '<NONCREATABLE>';
      eval {
        $tempfile = File::Temp->new(
          TEMPLATE => '_dbictest_writability_test_XXXXXX',
          DIR => "$dir",
          UNLINK => 1,
        );
        close $tempfile or die "closing $tempfile failed: $!\n";

        sysopen (my $tempfh2, "$tempfile", O_RDWR) or die "reopening $tempfile failed: $!\n";
        print $tempfh2 'deadbeef' x 1024 or die "printing to $tempfile failed: $!\n";
        close $tempfh2 or die "closing $tempfile failed: $!\n";
        1;
      } or do {
        chomp( my $err = $@ );
        my @x_tests = map { (defined $_) ? ( $_ ? 1 : 0 ) : 'U' } map {(-e, -d, -f, -r, -w, -x, -o)} ("$dir", "$tempfile");
        $reason_dir_unusable = sprintf <<"EOE", "$tempfile"||'', $err, scalar $>, scalar $), umask(), (stat($dir))[4,5,2], @x_tests;
File::Spec->tmpdir returned a directory which appears to be non-writeable:
Error encountered while testing '%s': %s
Process EUID/EGID: %s / %s
Effective umask:   %o
TmpDir UID/GID:    %s / %s
TmpDir StatMode:   %o
TmpDir X-tests:    -e:%s -d:%s -f:%s -r:%s -w:%s -x:%s -o:%s
TmpFile X-tests:   -e:%s -d:%s -f:%s -r:%s -w:%s -x:%s -o:%s
EOE
      };
    }

    if ($reason_dir_unusable) {
      # Replace with our local project tmpdir. This will make multiple runs
      # from different runs conflict with each other, but is much better than
      # polluting the root dir with random crap or failing outright
      my $local_dir = _find_co_root()->subdir('t')->subdir('var');
      $local_dir->mkpath;

      warn "\n\nUsing '$local_dir' as test scratch-dir instead of '$dir': $reason_dir_unusable\n";
      $dir = $local_dir;
    }

    $dir->stringify;
  });
}


# Die if the author did not update his makefile
#
# This is pretty heavy handed, so the check is pretty solid:
#
# 1) Assume that this particular module is loaded from -I <$root>/t/lib
# 2) Make sure <$root>/Makefile.PL exists
# 3) Make sure we can stat() <$root>/Makefile.PL
#
# If all of the above is satisfied
#
# *) die if <$root>/inc does not exist
# *) die if no stat() results for <$root>/Makefile (covers no Makefile)
# *) die if Makefile.PL mtime > Makefile mtime
#
sub _check_author_makefile {

  my $root = _find_co_root()
    or return;

  my $optdeps = file('lib/DBIx/Class/Optional/Dependencies.pm');

  # not using file->stat as it invokes File::stat which in turn breaks stat(_)
  my ($mf_pl_mtime, $mf_mtime, $optdeps_mtime) = ( map
    { (stat ($root->file ($_)) )[9] || undef }  # stat returns () on nonexistent files
    (qw|Makefile.PL  Makefile|, $optdeps)
  );

  return unless $mf_pl_mtime;   # something went wrong during co_root detection ?

  my @fail_reasons;

  if(not -d $root->subdir ('inc')) {
    push @fail_reasons, "Missing ./inc directory";
  }

  if(not $mf_mtime) {
    push @fail_reasons, "Missing ./Makefile";
  }
  else {
    if($mf_mtime < $mf_pl_mtime) {
      push @fail_reasons, "./Makefile.PL is newer than ./Makefile";
    }
    if($mf_mtime < $optdeps_mtime) {
      push @fail_reasons, "./$optdeps is newer than ./Makefile";
    }
  }

  if (@fail_reasons) {
    print STDERR <<'EOE';

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
======================== FATAL ERROR ===========================
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

We have a number of reasons to believe that this is a development
checkout and that you, the user, did not run `perl Makefile.PL`
before using this code. You absolutely _must_ perform this step,
to ensure you have all required dependencies present. Not doing
so often results in a lot of wasted time for other contributors
trying to assist you with spurious "its broken!" problems.

By default DBICs Makefile.PL turns all optional dependencies into
*HARD REQUIREMENTS*, in order to make sure that the entire test
suite is executed, and no tests are skipped due to missing modules.
If you for some reason need to disable this behavior - supply the
--skip_author_deps option when running perl Makefile.PL

If you are seeing this message unexpectedly (i.e. you are in fact
attempting a regular installation be it through CPAN or manually),
please report the situation to either the mailing list or to the
irc channel as described in

http://search.cpan.org/dist/DBIx-Class/lib/DBIx/Class.pm#GETTING_HELP/SUPPORT

The DBIC team


Reasons you received this message:

EOE

    foreach my $r (@fail_reasons) {
      print STDERR "  * $r\n";
    }
    print STDERR "\n\n\n";

    require Time::HiRes;
    Time::HiRes::sleep(0.005);
    print STDOUT "\nBail out!\n";
    exit 1;
  }
}

# Mimic $Module::Install::AUTHOR
sub is_author {

  my $root = _find_co_root()
    or return undef;

  return (
    ( not -d $root->subdir ('inc') )
      or
    ( -e $root->subdir ('inc')->subdir ($^O eq 'VMS' ? '_author' : '.author') )
  );
}

sub is_smoker {
  return (
    ( $ENV{AUTOMATED_TESTING} && ! $ENV{PERL5_CPANM_IS_RUNNING} && ! $ENV{RELEASE_TESTING} )
      or
    __PACKAGE__->is_ci
  );
}

sub is_ci {
  return (
    ($ENV{TRAVIS}||'') eq 'true'
      and
    ($ENV{TRAVIS_REPO_SLUG}||'') =~ m|\w+/dbix-class$|
  )
}

sub is_plain {
  return (
    ! $ENV{RELEASE_TESTING}
      and
    ! $ENV{DBICTEST_RUN_ALL_TESTS}
      and
    ! __PACKAGE__->is_smoker
      and
    ! __PACKAGE__->is_author
  )
}

1;
