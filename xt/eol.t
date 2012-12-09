use warnings;
use strict;

use Test::More;
use lib 't/lib';
use DBICTest;

require DBIx::Class;
unless ( DBIx::Class::Optional::Dependencies->req_ok_for ('test_eol') ) {
  my $missing = DBIx::Class::Optional::Dependencies->req_missing_for ('test_eol');
  $ENV{RELEASE_TESTING}
    ? die ("Failed to load release-testing module requirements: $missing")
    : plan skip_all => "Test needs: $missing"
}

Test::EOL::all_perl_files_ok({ trailing_whitespace => 1 },
  qw/t xt lib script examples maint .generated_pod/,
);

# Changes is not a "perl file", hence checked separately
Test::EOL::eol_unix_ok('Changes', { trailing_whitespace => 1 });

# FIXME - Test::EOL declares 'no_plan' which conflicts with done_testing
# https://github.com/schwern/test-more/issues/14
#done_testing;
