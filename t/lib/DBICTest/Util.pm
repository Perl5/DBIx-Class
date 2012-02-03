package DBICTest::Util;

use warnings;
use strict;

use Carp;
use Scalar::Util qw/isweak weaken blessed reftype refaddr/;
use Config;

use base 'Exporter';
our @EXPORT_OK = qw/local_umask stacktrace populate_weakregistry assert_empty_weakregistry/;

sub local_umask {
  return unless defined $Config{d_umask};

  die 'Calling local_umask() in void context makes no sense'
    if ! defined wantarray;

  my $old_umask = umask(shift());
  die "Setting umask failed: $!" unless defined $old_umask;

  return bless \$old_umask, 'DBICTest::Util::UmaskGuard';
}
{
  package DBICTest::Util::UmaskGuard;
  sub DESTROY {
    local ($@, $!);
    eval { defined (umask ${$_[0]}) or die };
    warn ( "Unable to reset old umask ${$_[0]}: " . ($!||'Unknown error') )
      if ($@ || $!);
  }
}


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

my $refs_traced = 0;
sub populate_weakregistry {
  my ($reg, $target, $slot) = @_;

  croak 'Target is not a reference' unless defined ref $target;

  $slot ||= (sprintf '%s%s(0x%x)', # so we don't trigger stringification
    (defined blessed $target) ? blessed($target) . '=' : '',
    reftype $target,
    refaddr $target,
  );

  if (defined $reg->{$slot}{weakref}) {
    if ( refaddr($reg->{$slot}{weakref}) != (refaddr $target) ) {
      print STDERR "Bail out! Weak Registry slot collision: $reg->{$slot}{weakref} / $target\n";
      exit 255;
    }
  }
  else {
    $refs_traced++;
    weaken( $reg->{$slot}{weakref} = $target );
    $reg->{$slot}{stacktrace} = stacktrace(1);
  }

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
