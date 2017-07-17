BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;

use Test::More;
use Test::Exception;

use DBICTest;

my $schema = DBICTest->init_schema();

# this has been warning for 4 years, killing
throws_ok {
  $schema->resultset('Artist')->find(artistid => 4);
} qr|expects either a column/value hashref, or a list of values corresponding to the columns of the specified unique constraint|;

{
  my $exception_callback_count = 0;

  my $ea = $schema->exception_action(sub {
    $exception_callback_count++;
    die @_;
  });

  # No, this is not a great idea.
  # Yes, people do it anyway.
  # Might as well test that we have fixed it for good, by never invoking
  # a potential __DIE__ handler in internal_try() stacks
  local $SIG{__DIE__} = sub { $ea->(@_) };

  # test find on non-unique non-existing value
  is (
    $schema->resultset('Artist')->find({ rank => 666 }),
    undef
  );

  # test find on an unresolvable condition
  is(
    $schema->resultset('Artist')->find({ artistid => [ -and => 1, 2 ]}),
    undef
  );

  is $exception_callback_count, 0, 'exception_callback never invoked';
}

done_testing;
