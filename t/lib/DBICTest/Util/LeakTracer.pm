package DBICTest::Util::LeakTracer;

use warnings;
use strict;

use Carp;
use Scalar::Util qw(isweak weaken blessed reftype);
use DBIx::Class::_Util 'refcount';
use Data::Dumper::Concise;
use DBICTest::Util 'stacktrace';

use base 'Exporter';
our @EXPORT_OK = qw(populate_weakregistry assert_empty_weakregistry hrefaddr);

my $refs_traced = 0;
my $leaks_found = 0;
my %reg_of_regs;

sub hrefaddr { sprintf '0x%x', &Scalar::Util::refaddr }

# so we don't trigger stringification
sub _describe_ref {
  sprintf '%s%s(%s)',
    (defined blessed $_[0]) ? blessed($_[0]) . '=' : '',
    reftype $_[0],
    hrefaddr $_[0],
  ;
}

sub populate_weakregistry {
  my ($weak_registry, $target, $note) = @_;

  croak 'Expecting a registry hashref' unless ref $weak_registry eq 'HASH';
  croak 'Target is not a reference' unless length ref $target;

  my $refaddr = hrefaddr $target;

  # a registry could be fed to itself or another registry via recursive sweeps
  return $target if $reg_of_regs{$refaddr};

  weaken( $reg_of_regs{ hrefaddr($weak_registry) } = $weak_registry )
    unless( $reg_of_regs{ hrefaddr($weak_registry) } );

  # an explicit "garbage collection" pass every time we store a ref
  # if we do not do this the registry will keep growing appearing
  # as if the traced program is continuously slowly leaking memory
  for my $reg (values %reg_of_regs) {
    (defined $reg->{$_}{weakref}) or delete $reg->{$_}
      for keys %$reg;
  }

  if (! defined $weak_registry->{$refaddr}{weakref}) {
    $weak_registry->{$refaddr} = {
      stacktrace => stacktrace(1),
      weakref => $target,
    };
    weaken( $weak_registry->{$refaddr}{weakref} );
    $refs_traced++;
  }

  my $desc = _describe_ref($target);
  $weak_registry->{$refaddr}{slot_names}{$desc} = 1;
  if ($note) {
    $note =~ s/\s*\Q$desc\E\s*//g;
    $weak_registry->{$refaddr}{slot_names}{$note} = 1;
  }

  $target;
}

# Regenerate the slots names on a thread spawn
sub CLONE {
  my @individual_regs = grep { scalar keys %{$_||{}} } values %reg_of_regs;
  %reg_of_regs = ();

  for my $reg (@individual_regs) {
    my @live_slots = grep { defined $_->{weakref} } values %$reg
      or next;

    $reg = {};  # get a fresh hashref in the new thread ctx
    weaken( $reg_of_regs{hrefaddr($reg)} = $reg );

    for my $slot_info (@live_slots) {
      my $new_addr = hrefaddr $slot_info->{weakref};

      # replace all slot names
      $slot_info->{slot_names} = { map {
        my $name = $_;
        $name =~ s/\(0x[0-9A-F]+\)/sprintf ('(%s)', $new_addr)/ieg;
        ($name => 1);
      } keys %{$slot_info->{slot_names}} };

      $reg->{$new_addr} = $slot_info;
    }
  }
}

sub assert_empty_weakregistry {
  my ($weak_registry, $quiet) = @_;

  croak 'Expecting a registry hashref' unless ref $weak_registry eq 'HASH';

  return unless keys %$weak_registry;

  my $tb = eval { Test::Builder->new }
    or croak 'Calling test_weakregistry without a loaded Test::Builder makes no sense';

  for my $addr (keys %$weak_registry) {
    $weak_registry->{$addr}{display_name} = join ' | ', (
      sort
        { length $a <=> length $b or $a cmp $b }
        keys %{$weak_registry->{$addr}{slot_names}}
    );

    $tb->BAILOUT("!!!! WEAK REGISTRY SLOT $weak_registry->{$addr}{display_name} IS NOT A WEAKREF !!!!")
      if defined $weak_registry->{$addr}{weakref} and ! isweak( $weak_registry->{$addr}{weakref} );
  }

  # compile a list of refs stored as CAG class data, so we can skip them
  # intelligently below
  my ($classdata_refcounts, $symwalker, $refwalker);

  $refwalker = sub {
    return unless length ref $_[0];

    my $seen = $_[1] || {};
    return if $seen->{hrefaddr $_[0]}++;

    $classdata_refcounts->{hrefaddr $_[0]}++;

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

    for my $refaddr (keys %$weak_registry) {
      if (
        defined $weak_registry->{$refaddr}{weakref}
          and
        my $expected_refcnt = $classdata_refcounts->{$refaddr}
      ) {
        delete $weak_registry->{$refaddr}
          if refcount($weak_registry->{$refaddr}{weakref}) == $expected_refcnt;
      }
    }
  }

  for my $addr (sort { $weak_registry->{$a}{display_name} cmp $weak_registry->{$b}{display_name} } keys %$weak_registry) {

    next if ! defined $weak_registry->{$addr}{weakref};

    $leaks_found++;
    $tb->ok (0, "Leaked $weak_registry->{$addr}{display_name}");

    my $diag = do {
      local $Data::Dumper::Maxdepth = 1;
      sprintf "\n%s (refcnt %d) => %s\n",
        $weak_registry->{$addr}{display_name},
        refcount($weak_registry->{$addr}{weakref}),
        (
          ref($weak_registry->{$addr}{weakref}) eq 'CODE'
            and
          B::svref_2object($weak_registry->{$addr}{weakref})->XSUB
        ) ? '__XSUB__' : Dumper( $weak_registry->{$addr}{weakref} )
      ;
    };

    $diag .= Devel::FindRef::track ($weak_registry->{$addr}{weakref}, 20) . "\n"
      if ( $ENV{TEST_VERBOSE} && eval { require Devel::FindRef });

    $diag =~ s/^/    /mg;

    if (my $stack = $weak_registry->{$addr}{stacktrace}) {
      $diag .= "    Reference first seen$stack";
    }

    $tb->diag($diag);
  }

  if (! $quiet and ! $leaks_found) {
    $tb->ok(1, sprintf "No leaks found at %s line %d", (caller())[1,2] );
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
