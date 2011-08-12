package DBIx::Class::Carp;

use strict;
use warnings;

# This is here instead of DBIx::Class because of load-order issues
BEGIN {
  # something is tripping up V::M on 5.8.1, leading  to segfaults.
  # A similar test in n::c itself is disabled on 5.8.1 for the same
  # reason. There isn't much motivation to try to find why it happens
  *DBIx::Class::_ENV_::BROKEN_NAMESPACE_CLEAN = ($] < 5.008005)
    ? sub () { 1 }
    : sub () { 0 }
  ;
}

use Carp ();
use namespace::clean ();

sub __find_caller {
  my ($skip_pattern, $class) = @_;

  my $skip_class_data = $class->_skip_namespace_frames
    if ($class and $class->can('_skip_namespace_frames'));

  $skip_pattern = qr/$skip_pattern|$skip_class_data/
    if $skip_class_data;

  my $fr_num = 1; # skip us and the calling carp*
  my @f;
  while (@f = caller($fr_num++)) {
    last unless $f[0] =~ $skip_pattern;

    if (
      $f[0]->can('_skip_namespace_frames')
        and
      my $extra_skip = $f[0]->_skip_namespace_frames
    ) {
      $skip_pattern = qr/$skip_pattern|$extra_skip/;
    }
  }

  my ($ln, $calling) = @f # if empty - nothing matched - full stack
    ? ( "at $f[1] line $f[2]", $f[3] )
    : ( Carp::longmess(), '{UNKNOWN}' )
  ;

  return (
    $ln,
    $calling =~ /::/ ? "$calling(): " : "$calling: ", # cargo-cult from Carp::Clan
  );
};

my $warn = sub {
  my ($ln, @warn) = @_;
  @warn = "Warning: something's wrong" unless @warn;

  # back-compat with Carp::Clan - a warning ending with \n does
  # not include caller info
  warn (
    @warn,
    $warn[-1] =~ /\n$/ ? '' : " $ln\n"
  );
};

sub import {
  my (undef, $skip_pattern) = @_;
  my $into = caller;

  $skip_pattern = $skip_pattern
    ? qr/ ^ $into $ | $skip_pattern /xo
    : qr/ ^ $into $ /xo
  ;

  no strict 'refs';

  *{"${into}::carp"} = sub {
    $warn->(
      __find_caller($skip_pattern, $into),
      @_
    );
  };

  my $fired;
  *{"${into}::carp_once"} = sub {
    return if $fired;
    $fired = 1;

    $warn->(
      __find_caller($skip_pattern, $into),
      @_,
    );
  };

  my $seen;
  *{"${into}::carp_unique"} = sub {
    my ($ln, $calling) = __find_caller($skip_pattern, $into);
    my $msg = join ('', $calling, @_);

    # unique carping with a hidden caller makes no sense
    $msg =~ s/\n+$//;

    return if $seen->{$ln}{$msg};
    $seen->{$ln}{$msg} = 1;

    $warn->(
      $ln,
      $msg,
    );
  };

  # cleanup after ourselves
  namespace::clean->import(-cleanee => $into, qw/carp carp_once carp_unique/)
    ## FIXME FIXME FIXME - something is tripping up V::M on 5.8.1, leading
    # to segfaults. When n::c/B::H::EndOfScope is rewritten in terms of tie()
    # see if this starts working
    unless DBIx::Class::_ENV_::BROKEN_NAMESPACE_CLEAN();
}

sub unimport {
  die (__PACKAGE__ . " does not implement unimport yet\n");
}

1;

=head1 NAME

DBIx::Class::Carp - Provides advanced Carp::Clan-like warning functions for DBIx::Class internals

=head1 DESCRIPTION

Documentation is lacking on purpose - this an experiment not yet fit for
mass consumption. If you use this do not count on any kind of stability,
in fact don't even count on this module's continuing existence (it has
been noindexed for a reason).

In addition to the classic interface:

  use DBIx::Class::Carp '^DBIx::Class'

this module also supports a class-data based way to specify the exclusion
regex. A message is only carped from a callsite that matches neither the
closed over string, nor the value of L</_skip_namespace_frames> as declared
on any callframe already skipped due to the same mechanism. This is to ensure
that intermediate callsites can declare their own additional skip-namespaces.

=head1 CLASS ATTRIBUTES

=head2 _skip_namespace_frames

A classdata attribute holding the stringified regex matching callsites that
should be skipped by the carp methods below. An empty string C<q{}> is treated
like no setting/C<undef> (the distinction is necessary due to semantics of the
class data accessors provided by L<Class::Accessor::Grouped>)

=head1 EXPORTED FUNCTIONS

This module export the following 3 functions. Only warning related C<carp*>
is being handled here, for C<croak>-ing you must use
L<DBIx::Class::Schema/throw_exception> or L<DBIx::Class::Exception>.

=head2 carp

Carps message with the file/line of the first callsite not matching
L</_skip_namespace_frames> nor the closed-over arguments to
C<use DBIx::Class::Carp>.

=head2 carp_unique

Like L</carp> but warns once for every distinct callsite (subject to the
same ruleset as L</carp>).

=head2 carp_once

Like L</carp> but warns only once for the life of the perl interpreter
(regardless of callsite).

=cut
