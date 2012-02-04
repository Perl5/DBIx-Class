# temporary(?) until I get around to fix M::I wrt xt/
# needs Module::Install::AuthorTests
eval {
  # this should not be necessary since the autoloader is supposed
  # to work, but there were reports of it failing
  require Module::Install::AuthorTests;
  recursive_author_tests (qw/xt/);
  1;
} || do {
  if (! $args->{skip_author_deps}) {
    my $err = $@;

    # better error message in case of missing dep
    eval { require Module::Install::AuthorTests }
      || die "\nYou need Module::Install::AuthorTests installed to run this Makefile.PL in author mode (or add --skip-author-deps):\n\n$@\n";

    die $err;
  }
};

# keep the Makefile.PL eval happy
1;
