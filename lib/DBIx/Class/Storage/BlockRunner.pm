package # hide from pause until we figure it all out
  DBIx::Class::Storage::BlockRunner;

use Sub::Quote 'quote_sub';
use DBIx::Class::Exception;
use DBIx::Class::Carp;
use Context::Preserve 'preserve_context';
use Scalar::Util qw/weaken blessed/;
use Try::Tiny;
use Moo;
use namespace::clean;

=head1 NAME

DBIx::Class::Storage::BlockRunner - Try running a block of code until success with a configurable retry logic

=head1 DESCRIPTION

=head1 METHODS

=cut

has storage => (
  is => 'ro',
  required => 1,
);

has wrap_txn => (
  is => 'ro',
  required => 1,
);

# true - retry, false - rethrow, or you can throw your own (not catching)
has retry_handler => (
  is => 'ro',
  required => 1,
  isa => quote_sub( q|
    (ref $_[0]) eq 'CODE'
      or DBIx::Class::Exception->throw('retry_handler must be a CODE reference')
  |),
);

has run_code => (
  is => 'ro',
  required => 1,
  isa => quote_sub( q|
    (ref $_[0]) eq 'CODE'
      or DBIx::Class::Exception->throw('run_code must be a CODE reference')
  |),
);

has run_args => (
  is => 'ro',
  isa => quote_sub( q|
    (ref $_[0]) eq 'ARRAY'
      or DBIx::Class::Exception->throw('run_args must be an ARRAY reference')
  |),
  default => quote_sub( '[]' ),
);

has retry_debug => (
  is => 'rw',
  default => quote_sub( '$ENV{DBIC_STORAGE_RETRY_DEBUG}' ),
);

has max_retried_count => (
  is => 'ro',
  default => quote_sub( '20' ),
);

has retried_count => (
  is => 'ro',
  init_arg => undef,
  writer => '_set_retried_count',
  clearer => '_reset_retried_count',
  default => quote_sub(q{ 0 }),
  lazy => 1,
  trigger => quote_sub(q{
    DBIx::Class::Exception->throw(sprintf (
      'Exceeded max_retried_count amount of %d, latest exception: %s',
      $_[0]->max_retried_count, $_[0]->last_exception
    )) if $_[0]->max_retried_count < ($_[1]||0);
  }),
);

has exception_stack => (
  is => 'ro',
  init_arg => undef,
  clearer => '_reset_exception_stack',
  default => quote_sub(q{ [] }),
  lazy => 1,
);

sub last_exception { shift->exception_stack->[-1] }

sub run {
  my $self = shift;

  DBIx::Class::Exception->throw('run() takes no arguments') if @_;

  $self->_reset_exception_stack;
  $self->_reset_retried_count;
  my $storage = $self->storage;

  return $self->run_code->( @{$self->run_args} )
    if (! $self->wrap_txn and $storage->{_in_do_block});

  local $storage->{_in_do_block} = 1 unless $storage->{_in_do_block};

  return $self->_run;
}

# this is the actual recursing worker
sub _run {
  # warnings here mean I did not anticipate some ueber-complex case
  # fatal warnings are not warranted
  no warnings;
  use warnings;

  my $self = shift;

  # from this point on (defined $txn_init_depth) is an indicator for wrap_txn
  # save a bit on method calls
  my $txn_init_depth = $self->wrap_txn ? $self->storage->transaction_depth : undef;
  my $txn_begin_ok;

  my $run_err = '';

  weaken (my $weakself = $self);

  return preserve_context {
    try {
      if (defined $txn_init_depth) {
        $weakself->storage->txn_begin;
        $txn_begin_ok = 1;
      }
      $weakself->run_code->( @{$weakself->run_args} );
    } catch {
      $run_err = $_;
      (); # important, affects @_ below
    };
  } replace => sub {
    my @res = @_;

    my $storage = $weakself->storage;
    my $cur_depth = $storage->transaction_depth;

    if (defined $txn_init_depth and $run_err eq '') {
      my $delta_txn = (1 + $txn_init_depth) - $cur_depth;

      if ($delta_txn) {
        # a rollback in a top-level txn_do is valid-ish (seen in the wild and our own tests)
        carp (sprintf
          'Unexpected reduction of transaction depth by %d after execution of '
        . '%s, skipping txn_commit()',
          $delta_txn,
          $weakself->run_code,
        ) unless $delta_txn == 1 and $cur_depth == 0;
      }
      else {
        $run_err = eval { $storage->txn_commit; 1 } ? '' : $@;
      }
    }

    # something above threw an error (could be the begin, the code or the commit)
    if ($run_err ne '') {

      # attempt a rollback if we did begin in the first place
      if ($txn_begin_ok) {
        # some DBDs go crazy if there is nothing to roll back on, perform a soft-check
        my $rollback_exception = $storage->_seems_connected
          ? (! eval { $storage->txn_rollback; 1 }) ? $@ : ''
          : 'lost connection to storage'
        ;

        if ( $rollback_exception and (
          ! defined blessed $rollback_exception
            or
          ! $rollback_exception->isa('DBIx::Class::Storage::NESTED_ROLLBACK_EXCEPTION')
        ) ) {
          $run_err = "Transaction aborted: $run_err. Rollback failed: $rollback_exception";
        }
      }

      push @{ $weakself->exception_stack }, $run_err;

      # init depth of > 0 ( > 1 with AC) implies nesting - no retry attempt queries
      $storage->throw_exception($run_err) if (
        (
          defined $txn_init_depth
            and
          # FIXME - we assume that $storage->{_dbh_autocommit} is there if
          # txn_init_depth is there, but this is a DBI-ism
          $txn_init_depth > ( $storage->{_dbh_autocommit} ? 0 : 1 )
        ) or ! $weakself->retry_handler->($weakself)
      );

      $weakself->_set_retried_count($weakself->retried_count + 1);

      # we got that far - let's retry
      carp( sprintf 'Retrying %s (run %d) after caught exception: %s',
        $weakself->run_code,
        $weakself->retried_count + 1,
        $run_err,
      ) if $weakself->retry_debug;

      $storage->ensure_connected;
      # if txn_depth is > 1 this means something was done to the
      # original $dbh, otherwise we would not get past the preceeding if()
      $storage->throw_exception(sprintf
        'Unexpected transaction depth of %d on freshly connected handle',
        $storage->transaction_depth,
      ) if (defined $txn_init_depth and $storage->transaction_depth);

      return $weakself->_run;
    }

    return wantarray ? @res : $res[0];
  };
}

=head1 AUTHORS

see L<DBIx::Class>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
