use warnings;
use strict;

use Test::More;
use lib qw(t/lib);
use DBICTest;

# Don't run tests for installs
if ( DBICTest::RunMode->is_plain ) {
  plan( skip_all => "Author tests not required for installation" );
}

require DBIx::Class;
unless ( DBIx::Class::Optional::Dependencies->req_ok_for ('test_pod') ) {
  my $missing = DBIx::Class::Optional::Dependencies->req_missing_for ('test_pod');
  (! DBICTest::RunMode->is_plain && ! DBICTest::RunMode->is_smoker )
    ? die ("Failed to load release-testing module requirements: $missing")
    : plan skip_all => "Test needs: $missing"
}

Test::Pod::all_pod_files_ok();
