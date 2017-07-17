package DBIx::Class::Storage;

use strict;
use warnings;

use base qw/DBIx::Class/;
use mro 'c3';

BEGIN {
  no warnings 'once';
  @DBIx::Class::Storage::NESTED_ROLLBACK_EXCEPTION::ISA
    = 'DBIx::Class::Exception';
}

use DBIx::Class::Carp;
use DBIx::Class::Storage::BlockRunner;
use Scalar::Util qw/blessed weaken/;
use DBIx::Class::Storage::TxnScopeGuard;
use DBIx::Class::_Util qw( dbic_internal_try dbic_internal_catch fail_on_internal_call );
use namespace::clean;

__PACKAGE__->mk_group_accessors(simple => qw/debug schema transaction_depth auto_savepoint savepoints/);
__PACKAGE__->mk_group_accessors(component_class => 'cursor_class');

__PACKAGE__->cursor_class('DBIx::Class::Cursor');

sub cursor :DBIC_method_is_indirect_sugar {
  DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and fail_on_internal_call;
  shift->cursor_class(@_);
}

=head1 NAME

DBIx::Class::Storage - Generic Storage Handler

=head1 DESCRIPTION

A base implementation of common Storage methods.  For specific
information about L<DBI>-based storage, see L<DBIx::Class::Storage::DBI>.

=head1 METHODS

=head2 new

Arguments: $schema

Instantiates the Storage object.

=cut

sub new {
  my ($self, $schema) = @_;

  $self = ref $self if ref $self;

  my $new = bless( {
    savepoints => [],
  }, $self);

  $new->set_schema($schema);
  $new->debug(1)
    if $ENV{DBIX_CLASS_STORAGE_DBI_DEBUG} || $ENV{DBIC_TRACE};

  $new;
}

=head2 set_schema

Used to reset the schema class or object which owns this
storage object, such as during L<DBIx::Class::Schema/clone>.

=cut

sub set_schema {
  my ($self, $schema) = @_;
  $self->schema($schema);
  weaken $self->{schema} if ref $self->{schema};
}

=head2 connected

Returns true if we have an open storage connection, false
if it is not (yet) open.

=cut

sub connected { die "Virtual method!" }

=head2 disconnect

Closes any open storage connection unconditionally.

=cut

sub disconnect { die "Virtual method!" }

=head2 ensure_connected

Initiate a connection to the storage if one isn't already open.

=cut

sub ensure_connected { die "Virtual method!" }

=head2 throw_exception

Throws an exception - croaks.

=cut

sub throw_exception {
  my $self = shift;

  if (ref $self and $self->schema) {
    $self->schema->throw_exception(@_);
  }
  else {
    DBIx::Class::Exception->throw(@_);
  }
}

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
  try {
    $rs = $schema->txn_do($coderef);
  } dbic_internal_catch {
    my $error = shift;
    # Transaction failed
    die "something terrible has happened!"
      if ($error =~ /Rollback failed/);          # Rollback failed

    deal_with_failed_transaction();
  };

In a nested transaction (calling txn_do() from within a txn_do() coderef) only
the outermost transaction will issue a L</txn_commit>, and txn_do() can be
called in void, scalar and list context and it will behave as expected.

Please note that all of the code in your coderef, including non-DBIx::Class
code, is part of a transaction.  This transaction may fail out halfway, or
it may get partially double-executed (in the case that our DB connection
failed halfway through the transaction, in which case we reconnect and
restart the txn).  Therefore it is best that any side-effects in your coderef
are idempotent (that is, can be re-executed multiple times and get the
same result), and that you check up on your side-effects in the case of
transaction failure.

=cut

sub txn_do {
  my $self = shift;

  DBIx::Class::Storage::BlockRunner->new(
    storage => $self,
    wrap_txn => 1,
    retry_handler => sub {
      $_[0]->failed_attempt_count == 1
        and
      ! $_[0]->storage->connected
    },
  )->run(@_);
}

=head2 txn_begin

Starts a transaction.

See the preferred L</txn_do> method, which allows for
an entire code block to be executed transactionally.

=cut

sub txn_begin {
  my $self = shift;

  if($self->transaction_depth == 0) {
    $self->debugobj->txn_begin()
      if $self->debug;
    $self->_exec_txn_begin;
  }
  elsif ($self->auto_savepoint) {
    $self->svp_begin;
  }
  $self->{transaction_depth}++;

}

=head2 txn_commit

Issues a commit of the current transaction.

It does I<not> perform an actual storage commit unless there's a DBIx::Class
transaction currently in effect (i.e. you called L</txn_begin>).

=cut

sub txn_commit {
  my $self = shift;

  if ($self->transaction_depth == 1) {
    $self->debugobj->txn_commit() if $self->debug;
    $self->_exec_txn_commit;
    $self->{transaction_depth}--;
    $self->savepoints([]);
  }
  elsif($self->transaction_depth > 1) {
    $self->{transaction_depth}--;
    $self->svp_release if $self->auto_savepoint;
  }
  else {
    $self->throw_exception( 'Refusing to commit without a started transaction' );
  }
}

=head2 txn_rollback

Issues a rollback of the current transaction. A nested rollback will
throw a L<DBIx::Class::Storage::NESTED_ROLLBACK_EXCEPTION> exception,
which allows the rollback to propagate to the outermost transaction.

=cut

sub txn_rollback {
  my $self = shift;

  if ($self->transaction_depth == 1) {
    $self->debugobj->txn_rollback() if $self->debug;
    $self->{transaction_depth}--;

    # in case things get really hairy - just disconnect
    dbic_internal_try { $self->_exec_txn_rollback; 1 } or do {
      my $rollback_error = $@;

      # whatever happens, too low down the stack to care
      # FIXME - revisit if stackable exceptions become a thing
      dbic_internal_try { $self->disconnect };

      die $rollback_error;
    };

    $self->savepoints([]);
  }
  elsif ($self->transaction_depth > 1) {
    $self->{transaction_depth}--;

    if ($self->auto_savepoint) {
      $self->svp_rollback;
      $self->svp_release;
    }
    else {
      DBIx::Class::Storage::NESTED_ROLLBACK_EXCEPTION->throw(
        "A txn_rollback in nested transaction is ineffective! (depth $self->{transaction_depth})"
      );
    }
  }
  else {
    $self->throw_exception( 'Refusing to roll back without a started transaction' );
  }
}

# to be called by several internal stacked transaction handler codepaths
# not for external consumption
# *DOES NOT* throw exceptions, instead:
#  - returns false on success
#  - returns the exception on failed rollback
sub __delicate_rollback {
  my $self = shift;

  if (
    ( $self->transaction_depth || 0 ) > 1
      and
    # FIXME - the autosvp check here shouldn't be happening, it should be a role-ish thing
    # The entire concept needs to be rethought with the storage layer... or something
    ! $self->auto_savepoint
      and
    # the handle seems healthy, and there is nothing for us to do with it
    # just go ahead and bow out, without triggering the txn_rollback() "nested exception"
    # the unwind will eventually fail somewhere higher up if at all
    # FIXME: a ::Storage::DBI-specific method, not a generic ::Storage one
    $self->_seems_connected
  ) {
    # all above checks out - there is nothing to do on the $dbh itself
    # just a plain soft-decrease of depth
    $self->{transaction_depth}--;
    return;
  }

  my @args = @_;
  my $rbe;

  dbic_internal_try {
    $self->txn_rollback; 1
  }
  dbic_internal_catch {

    $rbe = $_;

    # we were passed an existing exception to augment (think DESTROY stacks etc)
    if (@args) {
      my ($exception) = @args;

      # append our text - THIS IS A TEMPORARY FIXUP!
      #
      # If the passed in exception is a reference, or an object we don't know
      # how to augment - flattening it is just damn rude
      if (
        # FIXME - a better way, not liable to destroy an existing exception needs
        # to be created. For the time being perpetuating the sin below in order
        # to break the deadlock of which yak is being shaved first
        0
          and
        length ref $$exception
          and
        (
          ! defined blessed $$exception
            or
          ! $$exception->isa( 'DBIx::Class::Exception' )
        )
      ) {

        ##################
        ### FIXME - TODO
        ##################

      }
      else {

        # SUCH HIDEOUS, MUCH AUGH! (and double WOW on the s/// at the end below)
        $rbe =~ s/ at .+? line \d+$//;

        (
          (
            defined blessed $$exception
              and
            $$exception->isa( 'DBIx::Class::Exception' )
          )
            ? (
              $$exception->{msg} =
                "Transaction aborted: $$exception->{msg}. Rollback failed: $rbe"
            )
            : (
              $$exception =
                "Transaction aborted: $$exception. Rollback failed: $rbe"
            )
        ) =~ s/Transaction aborted: (?=Transaction aborted:)//;
      }
    }
  };

  return $rbe;
}

=head2 svp_begin

Arguments: $savepoint_name?

Created a new savepoint using the name provided as argument. If no name
is provided, a random name will be used.

=cut

sub svp_begin {
  my ($self, $name) = @_;

  $self->throw_exception ("You can't use savepoints outside a transaction")
    unless $self->transaction_depth;

  my $exec = $self->can('_exec_svp_begin')
    or $self->throw_exception ("Your Storage implementation doesn't support savepoints");

  $name = $self->_svp_generate_name
    unless defined $name;

  push @{ $self->{savepoints} }, $name;

  $self->debugobj->svp_begin($name) if $self->debug;

  $exec->($self, $name);
}

sub _svp_generate_name {
  my ($self) = @_;
  return 'savepoint_'.scalar(@{ $self->{'savepoints'} });
}


=head2 svp_release

Arguments: $savepoint_name?

Release the savepoint provided as argument. If none is provided,
release the savepoint created most recently. This will implicitly
release all savepoints created after the one explicitly released as well.

=cut

sub svp_release {
  my ($self, $name) = @_;

  $self->throw_exception ("You can't use savepoints outside a transaction")
    unless $self->transaction_depth;

  my $exec = $self->can('_exec_svp_release')
    or $self->throw_exception ("Your Storage implementation doesn't support savepoints");

  if (defined $name) {
    my @stack = @{ $self->savepoints };
    my $svp = '';

    while( $svp ne $name ) {

      $self->throw_exception ("Savepoint '$name' does not exist")
        unless @stack;

      $svp = pop @stack;
    }

    $self->savepoints(\@stack); # put back what's left
  }
  else {
    $name = pop @{ $self->savepoints }
      or $self->throw_exception('No savepoints to release');;
  }

  $self->debugobj->svp_release($name) if $self->debug;

  $exec->($self, $name);
}

=head2 svp_rollback

Arguments: $savepoint_name?

Rollback to the savepoint provided as argument. If none is provided,
rollback to the savepoint created most recently. This will implicitly
release all savepoints created after the savepoint we rollback to.

=cut

sub svp_rollback {
  my ($self, $name) = @_;

  $self->throw_exception ("You can't use savepoints outside a transaction")
    unless $self->transaction_depth;

  my $exec = $self->can('_exec_svp_rollback')
    or $self->throw_exception ("Your Storage implementation doesn't support savepoints");

  if (defined $name) {
    my @stack = @{ $self->savepoints };
    my $svp;

    # a rollback doesn't remove the named savepoint,
    # only everything after it
    while (@stack and $stack[-1] ne $name) {
      pop @stack
    };

    $self->throw_exception ("Savepoint '$name' does not exist")
      unless @stack;

    $self->savepoints(\@stack); # put back what's left
  }
  else {
    $name = $self->savepoints->[-1]
      or $self->throw_exception('No savepoints to rollback');;
  }

  $self->debugobj->svp_rollback($name) if $self->debug;

  $exec->($self, $name);
}

=head2 txn_scope_guard

An alternative way of transaction handling based on
L<DBIx::Class::Storage::TxnScopeGuard>:

 my $txn_guard = $storage->txn_scope_guard;

 $result->col1("val1");
 $result->update;

 $txn_guard->commit;

If an exception occurs, or the guard object otherwise leaves the scope
before C<< $txn_guard->commit >> is called, the transaction will be rolled
back by an explicit L</txn_rollback> call. In essence this is akin to
using a L</txn_begin>/L</txn_commit> pair, without having to worry
about calling L</txn_rollback> at the right places. Note that since there
is no defined code closure, there will be no retries and other magic upon
database disconnection. If you need such functionality see L</txn_do>.

=cut

sub txn_scope_guard {
  return DBIx::Class::Storage::TxnScopeGuard->new($_[0]);
}

=head2 sql_maker

Returns a C<sql_maker> object - normally an object of class
C<DBIx::Class::SQLMaker>.

=cut

sub sql_maker { die "Virtual method!" }

=head2 debug

Causes trace information to be emitted on the L</debugobj> object.
(or C<STDERR> if L</debugobj> has not specifically been set).

This is the equivalent to setting L</DBIC_TRACE> in your
shell environment.

=head2 debugfh

An opportunistic proxy to L<< ->debugobj->debugfh(@_)
|DBIx::Class::Storage::Statistics/debugfh >>
If the currently set L</debugobj> does not have a L</debugfh> method, caling
this is a no-op.

=cut

sub debugfh {
    my $self = shift;

    if ($self->debugobj->can('debugfh')) {
        return $self->debugobj->debugfh(@_);
    }
}

=head2 debugobj

Sets or retrieves the object used for metric collection. Defaults to an instance
of L<DBIx::Class::Storage::Statistics> that is compatible with the original
method of using a coderef as a callback.  See the aforementioned Statistics
class for more information.

=cut

sub debugobj {
  my $self = shift;

  if (@_) {
    return $self->{debugobj} = $_[0];
  }

  $self->{debugobj} ||= do {
    if (my $profile = $ENV{DBIC_TRACE_PROFILE}) {
      require DBIx::Class::Storage::Debug::PrettyPrint;
      my @pp_args;

      if ($profile =~ /^\.?\//) {

        require DBIx::Class::Optional::Dependencies;
        if ( my $missing = DBIx::Class::Optional::Dependencies->req_missing_for ('config_file_reader') ) {
          $self->throw_exception("Unable to parse TRACE_PROFILE config file '$profile' without $missing");
        }

        my $cfg = dbic_internal_try {
          Config::Any->load_files({ files => [$profile], use_ext => 1 });
        } dbic_internal_catch {
          # sanitize the error message a bit
          $_ =~ s/at \s+ .+ Storage\.pm \s line \s \d+ $//x;
          $self->throw_exception("Failure processing \$ENV{DBIC_TRACE_PROFILE}: $_");
        };

        @pp_args = values %{$cfg->[0]};
      }
      else {
        @pp_args = { profile => $profile };
      }

      # FIXME - FRAGILE
      # Hash::Merge is a sorry piece of shit and tramples all over $@
      # *without* throwing an exception
      # This is a rather serious problem in the debug codepath
      # Insulate the condition here with a try{} until a review of
      # DBIx::Class::Storage::Debug::PrettyPrint takes place
      # we do rethrow the error unconditionally, the only reason
      # to try{} is to preserve the precise state of $@ (down
      # to the scalar (if there is one) address level)
      #
      # Yes I am aware this is fragile and TxnScopeGuard needs
      # a better fix. This is another yak to shave... :(
      dbic_internal_try {
        DBIx::Class::Storage::Debug::PrettyPrint->new(@pp_args);
      } dbic_internal_catch {
        $self->throw_exception($_);
      }
    }
    else {
      require DBIx::Class::Storage::Statistics;
      DBIx::Class::Storage::Statistics->new
    }
  };
}

=head2 debugcb

Sets a callback to be executed each time a statement is run; takes a sub
reference.  Callback is executed as $sub->($op, $info) where $op is
SELECT/INSERT/UPDATE/DELETE and $info is what would normally be printed.

See L</debugobj> for a better way.

=cut

sub debugcb {
    my $self = shift;

    if ($self->debugobj->can('callback')) {
        return $self->debugobj->callback(@_);
    }
}

=head2 cursor_class

The cursor class for this Storage object.

=cut

=head2 deploy

Deploy the tables to storage (CREATE TABLE and friends in a SQL-based
Storage class). This would normally be called through
L<DBIx::Class::Schema/deploy>.

=cut

sub deploy { die "Virtual method!" }

=head2 connect_info

The arguments of C<connect_info> are always a single array reference,
and are Storage-handler specific.

This is normally accessed via L<DBIx::Class::Schema/connection>, which
encapsulates its argument list in an arrayref before calling
C<connect_info> here.

=cut

sub connect_info { die "Virtual method!" }

=head2 select

Handle a select statement.

=cut

sub select { die "Virtual method!" }

=head2 insert

Handle an insert statement.

=cut

sub insert { die "Virtual method!" }

=head2 update

Handle an update statement.

=cut

sub update { die "Virtual method!" }

=head2 delete

Handle a delete statement.

=cut

sub delete { die "Virtual method!" }

=head2 select_single

Performs a select, fetch and return of data - handles a single row
only.

=cut

sub select_single { die "Virtual method!" }

=head2 columns_info_for

Returns metadata for the given source's columns.  This
is *deprecated*, and will be removed before 1.0.  You should
be specifying the metadata yourself if you need it.

=cut

sub columns_info_for { die "Virtual method!" }

=head1 ENVIRONMENT VARIABLES

=head2 DBIC_TRACE

If C<DBIC_TRACE> is set then trace information
is produced (as when the L</debug> method is set).

If the value is of the form C<1=/path/name> then the trace output is
written to the file C</path/name>.

This environment variable is checked when the storage object is first
created (when you call connect on your schema).  So, run-time changes
to this environment variable will not take effect unless you also
re-connect on your schema.

=head2 DBIC_TRACE_PROFILE

If C<DBIC_TRACE_PROFILE> is set, L<DBIx::Class::Storage::Debug::PrettyPrint>
will be used to format the output from C<DBIC_TRACE>.  The value it
is set to is the C<profile> that it will be used.  If the value is a
filename the file is read with L<Config::Any> and the results are
used as the configuration for tracing.  See L<SQL::Abstract::Tree/new>
for what that structure should look like.

=head2 DBIX_CLASS_STORAGE_DBI_DEBUG

Old name for DBIC_TRACE

=head1 SEE ALSO

L<DBIx::Class::Storage::DBI> - reference storage implementation using
SQL::Abstract and DBI.

=head1 FURTHER QUESTIONS?

Check the list of L<additional DBIC resources|DBIx::Class/GETTING HELP/SUPPORT>.

=head1 COPYRIGHT AND LICENSE

This module is free software L<copyright|DBIx::Class/COPYRIGHT AND LICENSE>
by the L<DBIx::Class (DBIC) authors|DBIx::Class/AUTHORS>. You can
redistribute it and/or modify it under the same terms as the
L<DBIx::Class library|DBIx::Class/COPYRIGHT AND LICENSE>.

=cut

1;
