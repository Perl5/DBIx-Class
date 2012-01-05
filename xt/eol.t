use warnings;
use strict;

use Test::More;
use lib 't/lib';
use DBICTest;

require DBIx::Class;
unless ( DBIx::Class::Optional::Dependencies->req_ok_for ('test_eol') ) {
  my $missing = DBIx::Class::Optional::Dependencies->req_missing_for ('test_eol');
  (! DBICTest::RunMode->is_plain && ! DBICTest::RunMode->is_smoker )
    ? die ("Failed to load release-testing module requirements: $missing")
    : plan skip_all => "Test needs: $missing"
}

Test::EOL::all_perl_files_ok({ trailing_whitespace => 1 },
  qw/t xt lib script/,
  DBICTest::RunMode->is_author ? ('maint') : (),
);

# FIXME - Test::EOL declares 'no_plan' which conflicts with done_testing
# https://github.com/schwern/test-more/issues/14
#done_testing;
