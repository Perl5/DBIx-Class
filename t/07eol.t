use warnings;
use strict;

use Test::More;
use lib 't/lib';
use DBICTest;

# Don't run tests for installs
unless ( DBICTest::AuthorCheck->is_author || $ENV{AUTOMATED_TESTING} || $ENV{RELEASE_TESTING} ) {
  plan( skip_all => "Author tests not required for installation" );
}

plan skip_all => 'Test::EOL very broken';

require DBIx::Class;
unless ( DBIx::Class::Optional::Dependencies->req_ok_for ('test_eol') ) {
  my $missing = DBIx::Class::Optional::Dependencies->req_missing_for ('test_eol');
  $ENV{RELEASE_TESTING} || DBICTest::AuthorCheck->is_author
    ? die ("Failed to load release-testing module requirements: $missing")
    : plan skip_all => "Test needs: $missing"
}

TODO: {
  local $TODO = 'Do not fix those yet - we have way too many branches out there, merging will be hell';
  Test::EOL::all_perl_files_ok({ trailing_whitespace => 1}, qw/t lib script maint/);
}

# FIXME - need to fix Test::EOL
#done_testing;
