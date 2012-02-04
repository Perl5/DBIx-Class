my ($optdep_msg, $opt_testdeps);

if ($args->{skip_author_deps}) {
  $optdep_msg = <<'EOW';

******************************************************************************
******************************************************************************
***                                                                        ***
*** IGNORING AUTHOR MODE: no optional test dependencies will be forced.    ***
***                                                                        ***
*** If you are using this checkout with the intention of submitting a DBIC ***
*** patch, you are *STRONGLY ENCOURAGED* to install all dependencies, so   ***
*** that every possible unit-test will run.                                ***
***                                                                        ***
******************************************************************************
******************************************************************************

EOW
}
else {
  $optdep_msg = <<'EOW';

******************************************************************************
******************************************************************************
***                                                                        ***
*** AUTHOR MODE: all optional test dependencies converted to hard requires ***
***       ( to disable re-run Makefile.PL with --skip-author-deps )        ***
***                                                                        ***
******************************************************************************
******************************************************************************

EOW

  require DBIx::Class::Optional::Dependencies;
  my %reqs_for_group = %{DBIx::Class::Optional::Dependencies->req_group_list};

  # exclude the rdbms_* groups which are for DBIC users
  $opt_testdeps = {
    map { %{$reqs_for_group{$_}} } grep { !/^rdbms_/ } keys %reqs_for_group
  };

  print "Including all optional deps\n";
  $reqs->{test_requires} = {
    %{$reqs->{test_requires}},
    %$opt_testdeps
  };
}

# nasty hook into both M::AI init and the prompter, so that the optdep message
# comes at the right places (on top and then right above the prompt)
{
  require Module::AutoInstall;
  no warnings 'redefine';
  no strict 'refs';

  for (qw/_prompt import/) {
    my $meth = "Module::AutoInstall::$_";
    my $orig = \&{$meth};
    *{$meth} = sub {
      print $optdep_msg;
      goto $orig;
    };
  }
}

# this will run after the Makefile is written and the main Makefile.PL terminates
#
END {
  # Re-write META.yml at the end to _exclude_ all forced build-requires (we do not
  # want to ship this) We are also not using M::I::AuthorRequires as this will be
  # an extra dep, and deps in Makefile.PL still suck
  # Also always test the result so we stop shipping borked dependency lists to CPAN

  # FIXME test_requires is not yet part of META
  my %original_build_requires = ( %$build_requires, %$test_requires );
  my @all_build_requires = @{delete Meta->{values}{build_requires}||[]};
  my %removed_build_requires;

  for (@all_build_requires) {
    if ($original_build_requires{$_->[0]}) {
      push @{Meta->{values}{build_requires}}, $_;
    }
    else {
      $removed_build_requires{$_->[0]} = $_->[1]
        unless $_->[0] eq 'ExtUtils::MakeMaker';
    }
  }

  if (keys %removed_build_requires) {
    print "Regenerating META with author requires excluded\n";
    Meta->write;
  }

  # test that we really took things away (just in case, happened twice somehow)
  if (! -f 'META.yml') {
    warn "No META.yml generated?! aborting...\n";
    unlink 'Makefile';
    exit 1;
  }
  my $meta = do { local @ARGV = 'META.yml'; local $/; <> };

  # this is safe as there is a fatal check earlier in the main Makefile.PL
  # to make sure there are no duplicates (i.e. $opt_testdeps does not contain
  # any real dependencies)
  my @illegal_leftovers = grep
    { $meta =~ /^ \s+ \Q$_\E \: \s+ /mx }
    ( sort keys %$opt_testdeps )
  ;

  if (@illegal_leftovers) {
    warn join ("\n",
      "\n\nFATAL FAIL! It looks like some author dependencies made it to the META.yml:\n",
      map { "\t$_" } @illegal_leftovers
    ) . "\n\n";
    unlink 'Makefile';
    exit 1;
  }
}

# keep the Makefile.PL eval happy
1;
