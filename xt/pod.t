use warnings;
use strict;

use Test::More;
use lib qw(t/lib);
use DBICTest;

require DBIx::Class;
unless ( DBIx::Class::Optional::Dependencies->req_ok_for ('test_pod') ) {
  my $missing = DBIx::Class::Optional::Dependencies->req_missing_for ('test_pod');
  $ENV{RELEASE_TESTING}
    ? die ("Failed to load release-testing module requirements: $missing")
    : plan skip_all => "Test needs: $missing"
}

# this has already been required but leave it here for CPANTS static analysis
require Test::Pod;

my $generated_pod_dir = 'maint/.Generated_Pod';
Test::Pod::all_pod_files_ok( 'lib', -d $generated_pod_dir ? $generated_pod_dir : () );
