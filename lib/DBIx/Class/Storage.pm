package DBIx::Class::Storage;

use strict;
use warnings;

package # Hide from PAUSE
    DBIx::Class::Storage::NESTED_ROLLBACK_EXCEPTION;

use overload '"' => sub {
  'DBIx::Class::Storage::NESTED_ROLLBACK_EXCEPTION'
};

sub new {
  my $class = shift;
  my $self = {};
  return bless $self, $class;
}

package DBIx::Class::Storage;

sub new { die "Virtual method!" }
sub set_schema { die "Virtual method!" }
sub debug { die "Virtual method!" }
sub debugcb { die "Virtual method!" }
sub debugfh { die "Virtual method!" }
sub debugobj { die "Virtual method!" }
sub cursor { die "Virtual method!" }
sub disconnect { die "Virtual method!" }
sub connected { die "Virtual method!" }
sub ensure_connected { die "Virtual method!" }
sub on_connect_do { die "Virtual method!" }
sub connect_info { die "Virtual method!" }
sub sql_maker { die "Virtual method!" }
sub txn_begin { die "Virtual method!" }
sub txn_commit { die "Virtual method!" }
sub txn_rollback { die "Virtual method!" }
sub insert { die "Virtual method!" }
sub update { die "Virtual method!" }
sub delete { die "Virtual method!" }
sub select { die "Virtual method!" }
sub select_single { die "Virtual method!" }
sub columns_info_for { die "Virtual method!" }
sub throw_exception { die "Virtual method!" }

=head2 txn_do

=over 4

=item Arguments: C<$coderef>, @coderef_args?

=item Return Value: The return value of $coderef

=back

Executes C<$coderef> with (optional) arguments C<@coderef_args> atomically,
returning its result (if any). If an exception is caught, a rollback is issued
and the exception is rethrown. If the rollback fails, (i.e. throws an
exception) an exception is thrown that includes a "Rollback failed" message.

For example,

  my $author_rs = $schema->resultset('Author')->find(1);
  my @titles = qw/Night Day It/;

  my $coderef = sub {
    # If any one of these fails, the entire transaction fails
    $author_rs->create_related('books', {
      title => $_
    }) foreach (@titles);

    return $author->books;
  };

  my $rs;
  eval {
    $rs = $schema->txn_do($coderef);
  };

  if ($@) {                                  # Transaction failed
    die "something terrible has happened!"   #
      if ($@ =~ /Rollback failed/);          # Rollback failed

    deal_with_failed_transaction();
  }

In a nested transaction (calling txn_do() from within a txn_do() coderef) only
the outermost transaction will issue a L</txn_commit>, and txn_do() can be
called in void, scalar and list context and it will behave as expected.

=cut

sub txn_do {
  my ($self, $coderef, @args) = @_;

  ref $coderef eq 'CODE' or $self->throw_exception
    ('$coderef must be a CODE reference');

  my (@return_values, $return_value);

  $self->txn_begin; # If this throws an exception, no rollback is needed

  my $wantarray = wantarray; # Need to save this since the context
                             # inside the eval{} block is independent
                             # of the context that called txn_do()
  eval {

    # Need to differentiate between scalar/list context to allow for
    # returning a list in scalar context to get the size of the list
    if ($wantarray) {
      # list context
      @return_values = $coderef->(@args);
    } elsif (defined $wantarray) {
      # scalar context
      $return_value = $coderef->(@args);
    } else {
      # void context
      $coderef->(@args);
    }
    $self->txn_commit;
  };

  if ($@) {
    my $error = $@;

    eval {
      $self->txn_rollback;
    };

    if ($@) {
      my $rollback_error = $@;
      my $exception_class = "DBIx::Class::Storage::NESTED_ROLLBACK_EXCEPTION";
      $self->throw_exception($error)  # propagate nested rollback
        if $rollback_error =~ /$exception_class/;

      $self->throw_exception(
        "Transaction aborted: $error. Rollback failed: ${rollback_error}"
      );
    } else {
      $self->throw_exception($error); # txn failed but rollback succeeded
    }
  }

  return $wantarray ? @return_values : $return_value;
}

1;
