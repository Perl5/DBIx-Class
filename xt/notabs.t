use warnings;
use strict;

use Test::More;
use File::Glob 'bsd_glob';
use lib 't/lib';
use DBICTest;

require DBIx::Class;
unless ( DBIx::Class::Optional::Dependencies->req_ok_for ('test_notabs') ) {
  my $missing = DBIx::Class::Optional::Dependencies->req_missing_for ('test_notabs');
  $ENV{RELEASE_TESTING}
    ? die ("Failed to load release-testing module requirements: $missing")
    : plan skip_all => "Test needs: $missing"
}

# FIXME - temporary workaround for RT#82033
# also add all scripts (no extension) and some extra extensions
# we want to check
{
  no warnings 'redefine';

  *Test::EOL::_is_perl_module = sub {
    $_[0] !~ /\./ || $_[0] =~ /\.(?:pm|pod|skip|json|proto)$/i || $_[0] =~ /::/;
  }
}

Test::NoTabs::all_perl_files_ok(
  qw/t xt lib script examples maint/,
);

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

  for my $fn (bsd_glob('*')) {
    next if $skipnames->{$fn};
    next unless -f $fn;
    Test::NoTabs::notabs_ok($fn);
  }
}

# FIXME - Test::NoTabs declares 'no_plan' which conflicts with done_testing
# https://github.com/schwern/test-more/issues/14
#done_testing;
