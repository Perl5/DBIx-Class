require File::Spec;
require File::Find;

my $xt_dirs;
File::Find::find(sub {
  return if $xt_dirs->{$File::Find::dir};
  $xt_dirs->{$File::Find::dir} = 1 if (
    $_ =~ /\.t$/ and -f $_
  );
}, 'xt');

my @xt_tests = map { File::Spec->catfile($_, '*.t') } sort keys %$xt_dirs;

# this will add the xt tests to the `make test` target among other things
Meta->tests(join (' ', map { $_ || () } Meta->tests, @xt_tests ) );

# inject an explicit xt test run, mainly to check the contents of
# lib and the generated POD's *before* anything is copied around
#
# at the end rerun the whitespace test in the distdir, to make sure everything
# is pristine
postamble <<"EOP";

dbic_clonedir_copy_generated_pod : test_xt

test_xt : pm_to_blib
@{[
  # When xt tests are explicitly requested, we want to run with RELEASE_TESTING=1
  # so that all optdeps are turned into a hard failure
  # However portably modifying ENV for a single command is surprisingly hard
  # So instead we (ab)use perl's ability to stack -e options, and simply modify
  # the ENV from within perl itself
  $mm_proto->test_via_harness(
    # perl cmd
    join( ' ',
      '$(ABSPERLRUN)',
      map { $mm_proto->quote_literal($_) } qw(-e $ENV{RELEASE_TESTING}=1;)
    ),
    # test list
    join( ' ',
      map { $mm_proto->quote_literal($_) } @xt_tests
    ),
  )
]}

create_distdir : dbic_distdir_retest_whitespace

dbic_distdir_retest_whitespace :
\t@{[
  $mm_proto->cd (
    '$(DISTVNAME)',
    $mm_proto->test_via_harness(
      # perl cmd
      join( ' ',
        '$(ABSPERLRUN)',
        map { $mm_proto->quote_literal($_) } qw(-Ilib -e $ENV{RELEASE_TESTING}=1;$ENV{DBICTEST_NO_MAKEFILE_VERIFICATION}=1;)
      ),
      'xt/whitespace.t'
    )
  )
]}

EOP

# keep the Makefile.PL eval happy
1;
