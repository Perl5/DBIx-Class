use strict;
use warnings;
use Test::More;
use lib qw(t/lib);

BEGIN {
  plan skip_all =>
    'Skipping RH perl performance bug tests as DBIC_NO_WARN_BAD_PERL set'
    if ( $ENV{DBIC_NO_WARN_BAD_PERL} );

  require DBICTest::RunMode;
  plan skip_all => 'Skipping as system appears to be a smoker'
    if DBICTest::RunMode->is_smoker;
}

# globalllock so that the test runs alone
use DBICTest ':GlobalLock';

use Benchmark;

# This is a rather unusual test.
# It does not test any aspect of DBIx::Class, but instead tests the
# perl installation this is being run under to see if it is:-
#  1. Potentially affected by a RH perl build bug
#  2. If so we do a performance test for the effect of
#     that bug.
#
# You can skip these tests by setting the DBIC_NO_WARN_BAD_PERL env
# variable
#
# If these tests fail then please read the section titled
# Perl Performance Issues on Red Hat Systems in
# L<DBIx::Class::Manual::Troubleshooting>

# we do a benchmark test filling an array with blessed/overloaded references,
# against an array filled with array refs.
# On a sane system the ratio between these operation sets is 1 - 1.5,
# whereas a bugged system gives a ratio of around 8
# we therefore consider there to be a problem if the ratio is >= $fail_ratio
my $fail_ratio = 3;

ok( $fail_ratio, "Testing for a blessed overload slowdown >= ${fail_ratio}x" );


my $results = timethese(
    -1,    # run for 1 WALL second each
    {
        no_bless => sub {
            my %h;
            for ( my $i = 0 ; $i < 10000 ; $i++ ) {
                $h{$i} = [];
            }
        },
        bless_overload => sub {
            use overload q(<) => sub { };
            my %h;
            for ( my $i = 0 ; $i < 10000 ; $i++ ) {
                $h{$i} = bless [] => 'main';
            }
        },
    },
);

my $ratio = $results->{no_bless}->iters / $results->{bless_overload}->iters;

cmp_ok( $ratio, '<', $fail_ratio, 'Overload/bless performance acceptable' )
  || diag(
    "\n",
    "This perl has a substantial slow down when handling large numbers\n",
    "of blessed/overloaded objects.  This can severely adversely affect\n",
    "the performance of DBIx::Class programs.  Please read the section\n",
    "in the Troubleshooting POD documentation entitled\n",
    "'Perl Performance Issues on Red Hat Systems'\n",
    "As this is an extremely serious condition, the only way to skip\n",
    "over this test is to --force the installation, or to look in the test\n",
    "file " . __FILE__ . "\n",
  );

# We will only check for the difference in bless handling (whether the
# bless applies to the reference or the referent) if we have seen a
# performance issue...

SKIP: {
    skip "Not checking for bless handling as performance is OK", 1
      if Test::Builder->new->is_passing;

    {
        package    # don't want this in PAUSE
          TestRHBug;
        use overload bool => sub { 0 }
    }

    sub _has_bug_34925 {
        my %thing;
        my $r1 = \%thing;
        my $r2 = \%thing;
        bless $r1 => 'TestRHBug';
        return !!$r2;
    }

    sub _possibly_has_bad_overload_performance {
        return $] < 5.008009 && !_has_bug_34925();
    }

    # If this next one fails then you almost certainly have a RH derived
    # perl with the performance bug
    # if this test fails, look at the section titled
    # "Perl Performance Issues on Red Hat Systems" in
    # L<DBIx::Class::Manual::Troubleshooting>
    # Basically you may suffer severe performance issues when running
    # DBIx::Class (and many other) modules.  Look at getting a fixed
    # version of the perl interpreter for your system.
    #
    ok( !_possibly_has_bad_overload_performance(),
        'Checking whether bless applies to reference not object' )
      || diag(
        "\n",
        "This perl is probably derived from a buggy Red Hat perl build\n",
        "Please read the section in the Troubleshooting POD documentation\n",
        "entitled 'Perl Performance Issues on Red Hat Systems'\n",
        "As this is an extremely serious condition, the only way to skip\n",
        "over this test is to --force the installation, or to look in the test\n",
        "file " . __FILE__ . "\n",
      );
}

done_testing;
