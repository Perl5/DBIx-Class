use warnings;
use strict;

use Test::More;

my @defined = grep { $ENV{$_} } qw/
  DATA_DUMPER_TEST
  DBICTEST_STORAGE_STRESS
  DBICTEST_FORK_STRESS
  DBICTEST_THREAD_STRESS
/;

$SIG{ALRM} = sub { die "\n\nENVCHECK prompt timeout\n\n\n" };
if (@defined) {
  diag join "\n",
    'The following ENV variables used to control the test suite, '
   .'but no longer do so, please remove them from your environment',
    @defined,
    '',
    '(press Enter to continue)',
  ;
  alarm(10);
  <>;
  alarm(0);
}
ok(1);

done_testing;
