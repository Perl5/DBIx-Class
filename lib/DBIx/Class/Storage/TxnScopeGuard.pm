package DBIx::Class::Storage::TxnScopeGuard;

use strict;
use warnings;
use Try::Tiny;
use Scalar::Util qw/weaken blessed/;
use DBIx::Class;
use DBIx::Class::Exception;
use DBIx::Class::Carp;
use namespace::clean;

my ($guards_count, $compat_handler, $foreign_handler);

sub new {
  my ($class, $storage) = @_;

  $storage->txn_begin;
  my $guard = bless [ 0, $storage, $storage->_dbh ], ref $class || $class;


  # install a callback carefully
  if (DBIx::Class::_ENV_::INVISIBLE_DOLLAR_AT and !$guards_count) {

    # if the thrown exception is a plain string, wrap it in our
    # own exception class
    # this is actually a pretty cool idea, may very well keep it
    # after perl is fixed
    $compat_handler ||= bless(
      sub {
        $@ = (blessed($_[0]) or ref($_[0]))
          ? $_[0]
          : bless ( { msg => $_[0] }, 'DBIx::Class::Exception')
        ;
        die;
      },
      '__TxnScopeGuard__FIXUP__',
    );

    if ($foreign_handler = $SIG{__DIE__}) {
      $SIG{__DIE__} = bless (
        sub {
          # we trust the foreign handler to do whatever it wants, all we do is set $@
          eval { $compat_handler->(@_) };
          $foreign_handler->(@_);
        },
        '__TxnScopeGuard__FIXUP__',
      );
    }
    else {
      $SIG{__DIE__} = $compat_handler;
    }
  }

  $guards_count++;

  weaken ($guard->[2]);
  $guard;
}

sub commit {
  my $self = shift;

  $self->[1]->txn_commit;
  $self->[0] = 1;
}

sub DESTROY {
  my ($dismiss, $storage) = @{$_[0]};

  $guards_count--;

  # don't touch unless it's ours, and there are no more of us left
  if (
    DBIx::Class::_ENV_::INVISIBLE_DOLLAR_AT
      and
    !$guards_count
  ) {

    if (ref $SIG{__DIE__} eq '__TxnScopeGuard__FIXUP__') {
      # restore what we saved
      if ($foreign_handler) {
        $SIG{__DIE__} = $foreign_handler;
      }
      else {
        delete $SIG{__DIE__};
      }
    }

    # make sure we do not leak the foreign one in case it exists
    undef $foreign_handler;
  }

  return if $dismiss;

  # if our dbh is not ours anymore, the weakref will go undef
  $storage->_verify_pid;
  return unless $_[0]->[2];

  my $exception = $@;

  {
    local $@;

    carp 'A DBIx::Class::Storage::TxnScopeGuard went out of scope without explicit commit or error. Rolling back.'
      unless $exception;

    my $rollback_exception;
    # do minimal connectivity check due to weird shit like
    # https://rt.cpan.org/Public/Bug/Display.html?id=62370
    try { $storage->_seems_connected && $storage->txn_rollback }
    catch { $rollback_exception = shift };

    if ( $rollback_exception and (
      ! defined blessed $rollback_exception
          or
      ! $rollback_exception->isa('DBIx::Class::Storage::NESTED_ROLLBACK_EXCEPTION')
    ) ) {
      # append our text - THIS IS A TEMPORARY FIXUP!
      # a real stackable exception object is in the works
      if (ref $exception eq 'DBIx::Class::Exception') {
        $exception->{msg} = "Transaction aborted: $exception->{msg} "
          ."Rollback failed: ${rollback_exception}";
      }
      elsif ($exception) {
        $exception = "Transaction aborted: ${exception} "
          ."Rollback failed: ${rollback_exception}";
      }
      else {
        carp (join ' ',
          "********************* ROLLBACK FAILED!!! ********************",
          "\nA rollback operation failed after the guard went out of scope.",
          'This is potentially a disastrous situation, check your data for',
          "consistency: $rollback_exception"
        );
      }
    }
  }

  $@ = $exception unless DBIx::Class::_ENV_::INVISIBLE_DOLLAR_AT;
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

=head1 METHODS

=head2 new

Creating an instance of this class will start a new transaction (by
implicitly calling L<DBIx::Class::Storage/txn_begin>. Expects a
L<DBIx::Class::Storage> object as its only argument.

=head2 commit

Commit the transaction, and stop guarding the scope. If this method is not
called and this object goes out of scope (e.g. an exception is thrown) then
the transaction is rolled back, via L<DBIx::Class::Storage/txn_rollback>

=cut

=head1 SEE ALSO

L<DBIx::Class::Schema/txn_scope_guard>.

=head1 AUTHOR

Ash Berlin, 2008.

Inspired by L<Scope::Guard> by chocolateboy.

This module is free software. It may be used, redistributed and/or modified
under the same terms as Perl itself.

=cut
