use warnings;
use strict;

use Test::More;
use lib 't/lib';
use DBICTest;

# Don't run tests for installs
if ( DBICTest::RunMode->is_plain ) {
  plan( skip_all => "Author tests not required for installation" );
}

require DBIx::Class;
unless ( DBIx::Class::Optional::Dependencies->req_ok_for ('test_notabs') ) {
  my $missing = DBIx::Class::Optional::Dependencies->req_missing_for ('test_notabs');
  (! DBICTest::RunMode->is_plain && ! DBICTest::RunMode->is_smoker )
    ? die ("Failed to load release-testing module requirements: $missing")
    : plan skip_all => "Test needs: $missing"
}

Test::NoTabs::all_perl_files_ok(
  qw/t xt lib script/,
  DBICTest::RunMode->is_author ? ('maint') : (),
);

# FIXME - need to fix Test::NoTabs - doesn't work with done_testing
#done_testing;
