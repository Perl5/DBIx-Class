package DBICTest::Util::LeakTracer;

use warnings;
use strict;

use Carp;
use Scalar::Util qw/isweak weaken blessed reftype refaddr/;
use DBIx::Class::_Util 'refcount';
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

  my $refaddr = refaddr $target;

  $slot ||= (sprintf '%s%s(0x%x)', # so we don't trigger stringification
    (defined blessed $target) ? blessed($target) . '=' : '',
    reftype $target,
    $refaddr,
  );

  if (defined $weak_registry->{$slot}{weakref}) {
    if ( $weak_registry->{$slot}{refaddr} != $refaddr ) {
      print STDERR "Bail out! Weak Registry slot collision $slot: $weak_registry->{$slot}{weakref} / $target\n";
      exit 255;
    }
  }
  else {
    $weak_registry->{$slot} = {
      stacktrace => stacktrace(1),
      refaddr => $refaddr,
      renumber => $_[2] ? 0 : 1,
    };
    weaken( $weak_registry->{$slot}{weakref} = $target );
    $refs_traced++;
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

      my $refaddr = $inst->{refaddr} = refaddr($inst);

      $slot =~ s/0x[0-9A-F]+/'0x' . sprintf ('0x%x', $refaddr)/ieg
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


  # compile a list of refs stored as CAG class data, so we can skip them
  # intelligently below
  my ($classdata_refcounts, $symwalker, $refwalker);

  $refwalker = sub {
    return unless length ref $_[0];

    my $seen = $_[1] || {};
    return if $seen->{refaddr $_[0]}++;

    $classdata_refcounts->{refaddr $_[0]}++;

    my $type = reftype $_[0];
    if ($type eq 'HASH') {
      $refwalker->($_, $seen) for values %{$_[0]};
    }
    elsif ($type eq 'ARRAY') {
      $refwalker->($_, $seen) for @{$_[0]};
    }
    elsif ($type eq 'REF') {
      $refwalker->($$_, $seen);
    }
  };

  $symwalker = sub {
    no strict 'refs';
    my $pkg = shift || '::';

    $refwalker->(${"${pkg}$_"}) for grep { $_ =~ /__cag_(?!pkg_gen__|supers__)/ } keys %$pkg;

    $symwalker->("${pkg}$_") for grep { $_ =~ /(?<!^main)::$/ } keys %$pkg;
  };

  # run things twice, some cycles will be broken, introducing new
  # candidates for pseudo-GC
  for (1,2) {
    undef $classdata_refcounts;

    $symwalker->();

    for my $slot (keys %$weak_registry) {
      if (
        defined $weak_registry->{$slot}{weakref}
          and
        my $expected_refcnt = $classdata_refcounts->{$weak_registry->{$slot}{refaddr}}
      ) {
        delete $weak_registry->{$slot}
          if refcount($weak_registry->{$slot}{weakref}) == $expected_refcnt;
      }
    }
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
