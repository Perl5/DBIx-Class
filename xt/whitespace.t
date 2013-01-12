use warnings;
use strict;

use Test::More;
use File::Glob 'bsd_glob';
use lib 't/lib';
use DBICTest;

require DBIx::Class;
unless ( DBIx::Class::Optional::Dependencies->req_ok_for ('test_whitespace') ) {
  my $missing = DBIx::Class::Optional::Dependencies->req_missing_for ('test_whitespace');
  $ENV{RELEASE_TESTING}
    ? die ("Failed to load release-testing module requirements: $missing")
    : plan skip_all => "Test needs: $missing"
}

# FIXME - temporary workaround for RT#82032, RT#82033
# also add all scripts (no extension) and some extra extensions
# we want to check
{
  no warnings 'redefine';
  my $is_pm = sub {
    $_[0] !~ /\./ || $_[0] =~ /\.(?:pm|pod|skip|sql|json|proto)$/i || $_[0] =~ /::/;
  };

  *Test::EOL::_is_perl_module = $is_pm;
  *Test::NoTabs::_is_perl_module = $is_pm;
}

my @pl_targets = qw/t xt lib script examples maint/;
Test::EOL::all_perl_files_ok({ trailing_whitespace => 1 }, @pl_targets);
Test::NoTabs::all_perl_files_ok(@pl_targets);

# check some non-"perl files" in the root separately
# use .gitignore as a guide of what to skip
# (or do not test at all if no .gitignore is found)
if (open(my $gi, '<', '.gitignore')) {
  my $skipnames;
  while (my $ln = <$gi>) {
    next if $ln =~ /^\s*$/;
    chomp $ln;
    $skipnames->{$_}++ for bsd_glob($ln);
  }

  # that we want to check anyway
  delete $skipnames->{'META.yml'};

  for my $fn (bsd_glob('*')) {
    next if $skipnames->{$fn};
    next unless -f $fn;
    Test::EOL::eol_unix_ok($fn, { trailing_whitespace => 1 });
    Test::NoTabs::notabs_ok($fn);
  }
}

# FIXME - Test::NoTabs and Test::EOL declare 'no_plan' which conflicts with done_testing
# https://github.com/schwern/test-more/issues/14
#done_testing;
