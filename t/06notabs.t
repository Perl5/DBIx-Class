use warnings;
use strict;

use Test::More;
use lib 't/lib';
use DBICTest;

# Don't run tests for installs
unless ( DBICTest::AuthorCheck->is_author || $ENV{AUTOMATED_TESTING} || $ENV{RELEASE_TESTING} ) {
  plan( skip_all => "Author tests not required for installation" );
}

require DBIx::Class;
unless ( DBIx::Class::Optional::Dependencies->req_ok_for ('test_notabs') ) {
  my $missing = DBIx::Class::Optional::Dependencies->req_missing_for ('test_notabs');
  $ENV{RELEASE_TESTING} || DBICTest::AuthorCheck->is_author
    ? die ("Failed to load release-testing module requirements: $missing")
    : plan skip_all => "Test needs: $missing"
}

Test::NoTabs::all_perl_files_ok(qw/t lib script maint/);

# FIXME - need to fix Test::NoTabs
#done_testing;
