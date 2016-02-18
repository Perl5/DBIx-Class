package DBIx::Class::Storage::TxnScopeGuard;

use strict;
use warnings;
use Scalar::Util qw(weaken blessed refaddr);
use DBIx::Class;
use DBIx::Class::_Util qw(is_exception detected_reinvoked_destructor);
use DBIx::Class::Carp;
use namespace::clean;

sub new {
  my ($class, $storage) = @_;

  my $guard = {
    inactivated => 0,
    storage => $storage,
  };

  # we are starting with an already set $@ - in order for things to work we need to
  # be able to recognize it upon destruction - store its weakref
  # recording it before doing the txn_begin stuff
  #
  # FIXME FRAGILE - any eval that fails but *does not* rethrow between here
  # and the unwind will trample over $@ and invalidate the entire mechanism
  # There got to be a saner way of doing this...
  #
  # Deliberately *NOT* using is_exception - if someone left a misbehaving
  # antipattern value in $@, it's not our business to whine about it
  if( defined $@ and length $@ ) {
    weaken(
      $guard->{existing_exception_ref} = (length ref $@) ? $@ : \$@
    );
  }

  $storage->txn_begin;

  weaken( $guard->{dbh} = $storage->_dbh );

  bless $guard, ref $class || $class;

  $guard;
}

sub commit {
  my $self = shift;

  $self->{storage}->throw_exception("Refusing to execute multiple commits on scope guard $self")
    if $self->{inactivated};

  # FIXME - this assumption may be premature: a commit may fail and a rollback
  # *still* be necessary. Currently I am not aware of such scenarious, but I
  # also know the deferred constraint handling is *severely* undertested.
  # Making the change of "fire txn and never come back to this" in order to
  # address RT#107159, but this *MUST* be reevaluated later.
  $self->{inactivated} = 1;
  $self->{storage}->txn_commit;
}

sub force_inactivate {
  my $self = shift;
  $self->{inactivated} = 1;
}

sub DESTROY {
  return if &detected_reinvoked_destructor;

  return if $_[0]->{inactivated};


  # grab it before we've done volatile stuff below
  my $current_exception = (
    is_exception $@
      and
    (
      ! defined $_[0]->{existing_exception_ref}
        or
      refaddr( (length ref $@) ? $@ : \$@ ) != refaddr($_[0]->{existing_exception_ref})
    )
  )
    ? $@
    : undef
  ;


  # if our dbh is not ours anymore, the $dbh weakref will go undef
  $_[0]->{storage}->_verify_pid unless DBIx::Class::_ENV_::BROKEN_FORK;
  return unless defined $_[0]->{dbh};


  carp 'A DBIx::Class::Storage::TxnScopeGuard went out of scope without explicit commit or error. Rolling back'
    unless defined $current_exception;


  if (
    my $rollback_exception = $_[0]->{storage}->__delicate_rollback(
      defined $current_exception
        ? \$current_exception
        : ()
    )
      and
    ! defined $current_exception
  ) {
    carp (join ' ',
      "********************* ROLLBACK FAILED!!! ********************",
      "\nA rollback operation failed after the guard went out of scope.",
      'This is potentially a disastrous situation, check your data for',
      "consistency: $rollback_exception"
    );
  }

  $@ = $current_exception
    if DBIx::Class::_ENV_::UNSTABLE_DOLLARAT;

  # Dummy NEXTSTATE ensuring the all temporaries on the stack are garbage
  # collected before leaving this scope. Depending on the code above, this
  # may very well be just a preventive measure guarding future modifications
  undef;
}

1;

__END__

=head1 NAME

DBIx::Class::Storage::TxnScopeGuard - Scope-based transaction handling

=head1 SYNOPSIS

 sub foo {
   my ($self, $schema) = @_;

   my $guard = $schema->txn_scope_guard;

   # Multiple database operations here

   $guard->commit;
 }

=head1 DESCRIPTION

An object that behaves much like L<Scope::Guard>, but hardcoded to do the
right thing with transactions in DBIx::Class.

If you get the urge to call a C<rollback> method on the guard object, you're
advised to instead wrap your scoped transaction using C<< L<eval BLOCK|perlfunc/eval> >>
or L<Try::Tiny> and throw an exception with C<< L<die()|perlfunc/die> >>.
Explicit rollbacks don't compose (or nest) nicely without unwinding the scope
via an exception.

A warning is emitted if the guard goes out of scope without being first
inactivated by L</commit> or an exception.

=head1 METHODS

=head2 new

Creating an instance of this class will start a new transaction (by
implicitly calling L<DBIx::Class::Storage/txn_begin>. Expects a
L<DBIx::Class::Storage> object as its only argument.

=head2 commit

Commit the transaction, and stop guarding the scope. If this method is not
called and this object goes out of scope (e.g. an exception is thrown) then
the transaction is rolled back, via L<DBIx::Class::Storage/txn_rollback>

=head2 force_inactivate

Forcibly inactivate the guard, causing it to stop guarding the scope without
committing.  You're advised not to use this and to throw an exception if you
want to abort the transaction.  See the L</DESCRIPTION>.

=cut

=head1 SEE ALSO

L<DBIx::Class::Schema/txn_scope_guard>.

L<Scope::Guard> by chocolateboy (inspiration for this module)

=head1 FURTHER QUESTIONS?

Check the list of L<additional DBIC resources|DBIx::Class/GETTING HELP/SUPPORT>.

=head1 COPYRIGHT AND LICENSE

This module is free software L<copyright|DBIx::Class/COPYRIGHT AND LICENSE>
by the L<DBIx::Class (DBIC) authors|DBIx::Class/AUTHORS>. You can
redistribute it and/or modify it under the same terms as the
L<DBIx::Class library|DBIx::Class/COPYRIGHT AND LICENSE>.
