require File::Spec;
require File::Find;

my $xt_dirs;
File::Find::find(sub {
  return if $xt_dirs->{$File::Find::dir};
  $xt_dirs->{$File::Find::dir} = 1 if (
    $_ =~ /\.t$/ and -f $_
  );
}, 'xt');

my $xt_tests = join (' ', map { File::Spec->catfile($_, '*.t') } sort keys %$xt_dirs );

# this will add the xt tests to the `make test` target among other things
Meta->tests(join (' ', map { $_ || () } Meta->tests, $xt_tests ) );

# inject an explicit xt test run for the create_distdir target
postamble <<"EOP";

create_distdir : test_xt

test_xt :
\tPERL_DL_NONLAZY=1 RELEASE_TESTING=1 \$(FULLPERLRUN) "-MExtUtils::Command::MM" "-e" "test_harness(\$(TEST_VERBOSE), 'inc', '\$(INST_LIB)', '\$(INST_ARCHLIB)')" $xt_tests

EOP


# keep the Makefile.PL eval happy
1;
