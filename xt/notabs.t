use warnings;
use strict;

use Test::More;
use lib 't/lib';
use DBICTest;

require DBIx::Class;
unless ( DBIx::Class::Optional::Dependencies->req_ok_for ('test_notabs') ) {
  my $missing = DBIx::Class::Optional::Dependencies->req_missing_for ('test_notabs');
  $ENV{RELEASE_TESTING}
    ? die ("Failed to load release-testing module requirements: $missing")
    : plan skip_all => "Test needs: $missing"
}

Test::NoTabs::all_perl_files_ok(
  qw/t xt lib script examples maint/,
);

# Changes is not a "perl file", hence checked separately
Test::NoTabs::notabs_ok('Changes');

# FIXME - Test::NoTabs declares 'no_plan' which conflicts with done_testing
# https://github.com/schwern/test-more/issues/14
#done_testing;
