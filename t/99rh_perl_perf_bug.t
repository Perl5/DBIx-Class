#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use lib qw(t/lib);

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

plan skip_all =>
  'Skipping RH perl performance bug tests as DBIC_NO_WARN_BAD_PERL set'
  if ( $ENV{DBIC_NO_WARN_BAD_PERL} );

eval "use Benchmark";
plan skip_all => 'needs Benchmark for testing' if $@;

plan tests => 2;

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

# If the test here fails, you are running a 5.88 or older perl which 
# has been patched to correct for an issue with bless/overload, but
# which *might* be susceptable to a severe performance issue caused
# by a partial fix.  The performance issue is tested for in the second
# test.
# If *this* test fails, but the other test is OK, then you have a fixed
# perl and no need to worry.
ok( !_possibly_has_bad_overload_performance(),
    'Checking not susceptable to bless/overload performance problem' );

my $results = timethese(
    -1,    # run for 1 CPU second each
    {
        overload => sub {
            use overload q(<) => sub { };
            my %h;
            for ( my $i = 0 ; $i < 5000 ; $i++ ) {
                $h{$i} = bless [] => 'main';
            }
        },
        nooverload => sub {
            my %h;
            for ( my $i = 0 ; $i < 5000 ; $i++ ) {
                $h{$i} = bless [] => 'main';
            }
          }
    }
);

# we are OK if there is less than a factor of 2 difference here
ok( ( ( $results->{nooverload}->iters / $results->{overload}->iters ) < 2 ),
    'Overload/bless performance acceptable' )
# if the test above failed, look at the section titled
# Perl Performance Issues on Red Hat Systems in
# L<DBIx::Class::Manual::Troubleshooting>
# Basically you may suffer severe performance issues when running
# DBIx::Class (and many other) modules.  Look at getting a fixed
# version of the perl interpreter for your system.
