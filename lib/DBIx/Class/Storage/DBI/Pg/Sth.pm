package DBIx::Class::Storage::DBI::Pg::Sth;
use strict;
use warnings;
use base 'Class::Accessor::Grouped';

__PACKAGE__->mk_group_accessors('simple' =>
                                    'storage',
                                    'cursor_id', 'cursor_sql',
                                    'cursor_created',
                                    'cursor_sth',
                                    'fetch_sql', 'fetch_sth',
                            );

=head1 NAME

DBIx::Class::Storage::DBI::Pg::Sth

=head1 DESCRIPTION

A statement wrapper to use PostgreSQL cursors on DBIx::Class C<SELECT>s

=head1 How this whole thing works

This class encapsulates I<two> DBI statements:

=over 4

=item *

one is used to declare the cursor in postgres (C<cursor_sth>)

=item *

the other is used to fetch records from the cursor (C<fetch_sth>)

=back

C<cursor_sth> is prepared as needed (in L</bind_param> or
L</execute>); it's executed in L</execute>. We need the bind
parameters to run it, and we don't want to prepare it if it won't be
used.

C<fetch_sth> is prepared and executed whenever we need to
fetch more records from the cursor. The algorithm, taken from the
documentation of L<DBD::Pg>, is:

  declare_the_cursor($name,@bind_params);
  while (1) {
    my $fetch_sth = prepare_and_execute_fetch_from($name);
    last if $fetch_sth->rows == 0; # cursor reached the end of the result set

    while (my $row = $fetch_sth->fetchrow_hashref) {
       use_the($row);
    }
  }
  close_the_cursor($name);

We implement the algorithm twice, in L</fetchrow_array> and in
L</fetchall_arrayref> (other statement methods are not used by
DBIx::Class, so we don't care about them).

C<cursor_sth> is kept in an attribute of this class because we may
prepare/bind it in L</bind_param> and execute it in
L</execute>. C<cursor_created> is used to create the cursor on demand
(if our "fetch" methods are called before L</execute>) and to avoid
doing it twice.

The name of the cursor created by this class is determined by the
calling Storage object. Cursors are per-connection, but so are
statements, which means that we don't have to care about
re-connections here. The Storage will sort it out.

=cut

sub new {
    my ($class, $storage, $dbh, $sql, $page_size) = @_;

    # sanity, DBIx::Class::Storage::DBI::Pg should never instantiate
    # this class for non-selects
    if ($sql =~ /^SELECT\b/i) {
        my $self=bless {},$class;
        $self->storage($storage);

        my $csr_id=$self->_cursor_name_from_number(
            $storage->_get_next_pg_cursor_number()
        );
        my $hold= ($sql =~ /\bFOR\s+UPDATE\s*\z/i) ? '' : 'WITH HOLD';
        # the SQL to create the cursor
        $self->cursor_sql("DECLARE $csr_id CURSOR $hold FOR $sql");
        # our id, used when fetching
        $self->cursor_id($csr_id);
        # we prepare this as late as possible
        $self->cursor_sth(undef);
        # we haven't created the cursor, yet
        $self->cursor_created(0);
        # the SQL to fetch records from the cursor
        $self->fetch_sql("FETCH $page_size FROM $csr_id");

        return $self;
    }
    else {
        die "Can only be used for SELECTs";
    }
}

sub _cursor_name_from_number {
    return 'dbic_pg_cursor_'.$_[1];
}

sub _prepare_cursor_sth {
    my ($self)=@_;

    return if $self->cursor_sth;

    $self->cursor_sth($self->storage->sth($self->cursor_sql));
}

sub _cleanup_sth {
    my ($self)=@_;

    if ($self->fetch_sth) {
        $self->fetch_sth->finish();
        $self->fetch_sth(undef);
    }
    if ($self->cursor_sth) {
        $self->cursor_sth->finish();
        $self->cursor_sth(undef);
        $self->storage->dbh->do('CLOSE '.$self->cursor_id);
    }
}

sub DESTROY {
    my ($self) = @_;

    local $@; # be nice to callers, don't clobber their exceptions
    eval { $self->_cleanup_sth };

    return;
}

sub bind_param {
    my ($self,@bind_args)=@_;

    $self->_prepare_cursor_sth;

    return $self->cursor_sth->bind_param(@bind_args);
}

sub execute {
    my ($self,@bind_values)=@_;

    $self->_prepare_cursor_sth;

    my $ret=$self->cursor_sth->execute(@bind_values);
    $self->cursor_created(1) if $ret;
    return $ret;
}

# bind_param_array & execute_array not used for SELECT statements, so
# we'll ignore them

sub errstr {
    my ($self)=@_;

    return $self->cursor_sth->errstr;
}

sub finish {
    my ($self)=@_;

    $self->fetch_sth->finish if $self->fetch_sth;
    return $self->cursor_sth->finish if $self->cursor_sth;
    return 1;
}

sub _check_cursor_end {
    my ($self) = @_;

    if ($self->fetch_sth->rows == 0) {
        $self->_cleanup_sth;
        return 1;
    }
    return;
}

sub _run_fetch_sth {
    my ($self)=@_;

    if (!$self->cursor_created) {
        $self->execute();
    }

    $self->fetch_sth->finish if $self->fetch_sth;
    $self->fetch_sth($self->storage->sth($self->fetch_sql));
    $self->fetch_sth->execute;
}

sub fetchrow_array {
    my ($self) = @_;

    # start fetching if we haven't already
    $self->_run_fetch_sth unless $self->fetch_sth;
    # no rows? the the cursor is at the end of the resultset, nothing
    # else to do
    return if $self->_check_cursor_end;

    # got a row
    my @row = $self->fetch_sth->fetchrow_array;
    if (!@row) {
        # hmm. no row came back, we are at the end of the page
        $self->_run_fetch_sth;
        # we are also at the end of the resultset? if so, return
        return if $self->_check_cursor_end;

        # get the row from the new page
        @row = $self->fetch_sth->fetchrow_array;
    }
    return @row;
}

sub fetchall_arrayref {
    my ($self,$slice,$max_rows) = @_;

    my $ret=[];

    # start fetching if we haven't already
    $self->_run_fetch_sth unless $self->fetch_sth;
    # no rows? the the cursor is at the end of the resultset, nothing
    # else to do
    return if $self->_check_cursor_end;

    while (1) {
        # get the whole page from the cursor
        my $batch=$self->fetch_sth->fetchall_arrayref($slice,$max_rows);

        push @$ret,@$batch;

        # take care to never return more than $max_rows
        if (defined($max_rows) && $max_rows >=0) {
            $max_rows -= @$batch;
            last if $max_rows <=0;
        }

        # if the page was empty, the cursor reached the end of the
        # resultset, get out of here
        last if @$batch ==0;

        # fetch a new page
        $self->_run_fetch_sth;
        # get out if this new page is empty
        last if $self->_check_cursor_end;
    }

    return $ret;
}

1;
