package DBICTest::Util::LeakTracer;

use warnings;
use strict;

use Carp;
use Scalar::Util qw/isweak weaken blessed reftype refaddr/;
use DBICTest::Util 'stacktrace';

use base 'Exporter';
our @EXPORT_OK = qw/populate_weakregistry assert_empty_weakregistry/;

my $refs_traced = 0;
my $leaks_found;
my %reg_of_regs;

sub populate_weakregistry {
  my ($weak_registry, $target, $slot) = @_;

  croak 'Expecting a registry hashref' unless ref $weak_registry eq 'HASH';
  croak 'Target is not a reference' unless length ref $target;

  $slot ||= (sprintf '%s%s(0x%x)', # so we don't trigger stringification
    (defined blessed $target) ? blessed($target) . '=' : '',
    reftype $target,
    refaddr $target,
  );

  if (defined $weak_registry->{$slot}{weakref}) {
    if ( refaddr($weak_registry->{$slot}{weakref}) != (refaddr $target) ) {
      print STDERR "Bail out! Weak Registry slot collision: $weak_registry->{$slot}{weakref} / $target\n";
      exit 255;
    }
  }
  else {
    $refs_traced++;
    weaken( $weak_registry->{$slot}{weakref} = $target );
    $weak_registry->{$slot}{stacktrace} = stacktrace(1);
    $weak_registry->{$slot}{renumber} = 1 unless $_[2];
  }

  weaken( $reg_of_regs{ refaddr($weak_registry) } = $weak_registry )
    unless( $reg_of_regs{ refaddr($weak_registry) } );

  $target;
}

# Renumber everything we auto-named on a thread spawn
sub CLONE {
  my @individual_regs = grep { scalar keys %{$_||{}} } values %reg_of_regs;
  %reg_of_regs = ();

  for my $reg (@individual_regs) {
    my @live_slots = grep { defined $reg->{$_}{weakref} } keys %$reg
      or next;

    my @live_instances = @{$reg}{@live_slots};

    $reg = {};  # get a fresh hashref in the new thread ctx
    weaken( $reg_of_regs{refaddr($reg)} = $reg );

    while (@live_slots) {
      my $slot = shift @live_slots;
      my $inst = shift @live_instances;

      $slot =~ s/0x[0-9A-F]+/'0x' . sprintf ('0x%x', refaddr($inst))/ieg
        if $inst->{renumber};

      $reg->{$slot} = $inst;
    }
  }
}

sub assert_empty_weakregistry {
  my ($weak_registry, $quiet) = @_;

  croak 'Expecting a registry hashref' unless ref $weak_registry eq 'HASH';

  return unless keys %$weak_registry;

  my $tb = eval { Test::Builder->new }
    or croak 'Calling test_weakregistry without a loaded Test::Builder makes no sense';

  for my $slot (sort keys %$weak_registry) {
    next if ! defined $weak_registry->{$slot}{weakref};
    $tb->BAILOUT("!!!! WEAK REGISTRY SLOT $slot IS NOT A WEAKREF !!!!")
      unless isweak( $weak_registry->{$slot}{weakref} );
  }


  for my $slot (sort keys %$weak_registry) {
    ! defined $weak_registry->{$slot}{weakref} and next if $quiet;

    $tb->ok (! defined $weak_registry->{$slot}{weakref}, "No leaks of $slot") or do {
      $leaks_found = 1;

      my $diag = '';

      $diag .= Devel::FindRef::track ($weak_registry->{$slot}{weakref}, 20) . "\n"
        if ( $ENV{TEST_VERBOSE} && eval { require Devel::FindRef });

      if (my $stack = $weak_registry->{$slot}{stacktrace}) {
        $diag .= "    Reference first seen$stack";
      }

      $tb->diag($diag) if $diag;
    };
  }
}

END {
  if ($INC{'Test/Builder.pm'}) {
    my $tb = Test::Builder->new;

    # we check for test passage - a leak may be a part of a TODO
    if ($leaks_found and !$tb->is_passing) {

      $tb->diag(sprintf
        "\n\n%s\n%s\n\nInstall Devel::FindRef and re-run the test with set "
      . '$ENV{TEST_VERBOSE} (prove -v) to see a more detailed leak-report'
      . "\n\n%s\n%s\n\n", ('#' x 16) x 4
      ) if ( !$ENV{TEST_VERBOSE} or !$INC{'Devel/FindRef.pm'} );

    }
    else {
      $tb->note("Auto checked $refs_traced references for leaks - none detected");
    }
  }
}

1;
