package DBICTest::Util;

use warnings;
use strict;

use Carp;
use Scalar::Util qw/isweak weaken blessed reftype refaddr/;

use base 'Exporter';
our @EXPORT_OK = qw/stacktrace populate_weakregistry assert_empty_weakregistry/;

sub stacktrace {
  my $frame = shift;
  $frame++;
  my (@stack, @frame);

  while (@frame = caller($frame++)) {
    push @stack, [@frame[3,1,2]];
  }

  return undef unless @stack;

  $stack[0][0] = '';
  return join "\tinvoked as ", map { sprintf ("%s at %s line %d\n", @$_ ) } @stack;
}

sub populate_weakregistry {
  my ($reg, $target, $slot) = @_;


  croak 'Target is not a reference' unless defined ref $target;

  $slot ||= (sprintf '%s%s(0x%x)', # so we don't trigger stringification
    (defined blessed $target) ? blessed($target) . '=' : '',
    reftype $target,
    refaddr $target,
  );

  weaken( $reg->{$slot}{weakref} = $target );
  $reg->{$slot}{stacktrace} = stacktrace(1);

  $target;
}

my $leaks_found;
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
  if ($leaks_found) {
    my $tb = Test::Builder->new;
    $tb->diag(sprintf
      "\n\n%s\n%s\n\nInstall Devel::FindRef and re-run the test with set "
    . '$ENV{TEST_VERBOSE} (prove -v) to see a more detailed leak-report'
    . "\n\n%s\n%s\n\n", ('#' x 16) x 4
    ) if (!$tb->is_passing and (!$ENV{TEST_VERBOSE} or !$INC{'Devel/FindRef.pm'}));
  }
}

1;
