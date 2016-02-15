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


# Mimic $Module::Install::AUTHOR
sub is_author {

  return (
    ! -d 'inc/Module'
      or
    -e 'inc/.author'
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
