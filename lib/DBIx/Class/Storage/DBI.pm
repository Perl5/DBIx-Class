package DBIx::Class::Storage::DBI;
# -*- mode: cperl; cperl-indent-level: 2 -*-

use base 'DBIx::Class::Storage';

use strict;
use warnings;
use DBI;
use SQL::Abstract::Limit;
use DBIx::Class::Storage::DBI::Cursor;
use DBIx::Class::Storage::Statistics;
use IO::File;

__PACKAGE__->mk_group_accessors(
  'simple' =>
    qw/_connect_info _dbh _sql_maker _sql_maker_opts _conn_pid _conn_tid
       cursor on_connect_do transaction_depth/
);

BEGIN {

package DBIC::SQL::Abstract; # Would merge upstream, but nate doesn't reply :(

use base qw/SQL::Abstract::Limit/;

# This prevents the caching of $dbh in S::A::L, I believe
sub new {
  my $self = shift->SUPER::new(@_);

  # If limit_dialect is a ref (like a $dbh), go ahead and replace
  #   it with what it resolves to:
  $self->{limit_dialect} = $self->_find_syntax($self->{limit_dialect})
    if ref $self->{limit_dialect};

  $self;
}

sub _RowNumberOver {
  my ($self, $sql, $order, $rows, $offset ) = @_;

  $offset += 1;
  my $last = $rows + $offset;
  my ( $order_by ) = $self->_order_by( $order );

  $sql = <<"";
SELECT * FROM
(
   SELECT Q1.*, ROW_NUMBER() OVER( ) AS ROW_NUM FROM (
      $sql
      $order_by
   ) Q1
) Q2
WHERE ROW_NUM BETWEEN $offset AND $last

  return $sql;
}


# While we're at it, this should make LIMIT queries more efficient,
#  without digging into things too deeply
sub _find_syntax {
  my ($self, $syntax) = @_;
  my $dbhname = ref $syntax eq 'HASH' ? $syntax->{Driver}{Name} : '';
  if(ref($self) && $dbhname && $dbhname eq 'DB2') {
    return 'RowNumberOver';
  }

  $self->{_cached_syntax} ||= $self->SUPER::_find_syntax($syntax);
}

sub select {
  my ($self, $table, $fields, $where, $order, @rest) = @_;
  $table = $self->_quote($table) unless ref($table);
  local $self->{rownum_hack_count} = 1
    if (defined $rest[0] && $self->{limit_dialect} eq 'RowNum');
  @rest = (-1) unless defined $rest[0];
  die "LIMIT 0 Does Not Compute" if $rest[0] == 0;
    # and anyway, SQL::Abstract::Limit will cause a barf if we don't first
  local $self->{having_bind} = [];
  my ($sql, @ret) = $self->SUPER::select(
    $table, $self->_recurse_fields($fields), $where, $order, @rest
  );
  return wantarray ? ($sql, @ret, @{$self->{having_bind}}) : $sql;
}

sub insert {
  my $self = shift;
  my $table = shift;
  $table = $self->_quote($table) unless ref($table);
  $self->SUPER::insert($table, @_);
}

sub update {
  my $self = shift;
  my $table = shift;
  $table = $self->_quote($table) unless ref($table);
  $self->SUPER::update($table, @_);
}

sub delete {
  my $self = shift;
  my $table = shift;
  $table = $self->_quote($table) unless ref($table);
  $self->SUPER::delete($table, @_);
}

sub _emulate_limit {
  my $self = shift;
  if ($_[3] == -1) {
    return $_[1].$self->_order_by($_[2]);
  } else {
    return $self->SUPER::_emulate_limit(@_);
  }
}

sub _recurse_fields {
  my ($self, $fields) = @_;
  my $ref = ref $fields;
  return $self->_quote($fields) unless $ref;
  return $$fields if $ref eq 'SCALAR';

  if ($ref eq 'ARRAY') {
    return join(', ', map {
      $self->_recurse_fields($_)
      .(exists $self->{rownum_hack_count}
         ? ' AS col'.$self->{rownum_hack_count}++
         : '')
     } @$fields);
  } elsif ($ref eq 'HASH') {
    foreach my $func (keys %$fields) {
      return $self->_sqlcase($func)
        .'( '.$self->_recurse_fields($fields->{$func}).' )';
    }
  }
}

sub _order_by {
  my $self = shift;
  my $ret = '';
  my @extra;
  if (ref $_[0] eq 'HASH') {
    if (defined $_[0]->{group_by}) {
      $ret = $self->_sqlcase(' group by ')
               .$self->_recurse_fields($_[0]->{group_by});
    }
    if (defined $_[0]->{having}) {
      my $frag;
      ($frag, @extra) = $self->_recurse_where($_[0]->{having});
      push(@{$self->{having_bind}}, @extra);
      $ret .= $self->_sqlcase(' having ').$frag;
    }
    if (defined $_[0]->{order_by}) {
      $ret .= $self->_order_by($_[0]->{order_by});
    }
  } elsif (ref $_[0] eq 'SCALAR') {
    $ret = $self->_sqlcase(' order by ').${ $_[0] };
  } elsif (ref $_[0] eq 'ARRAY' && @{$_[0]}) {
    my @order = @{+shift};
    $ret = $self->_sqlcase(' order by ')
          .join(', ', map {
                        my $r = $self->_order_by($_, @_);
                        $r =~ s/^ ?ORDER BY //i;
                        $r;
                      } @order);
  } else {
    $ret = $self->SUPER::_order_by(@_);
  }
  return $ret;
}

sub _order_directions {
  my ($self, $order) = @_;
  $order = $order->{order_by} if ref $order eq 'HASH';
  return $self->SUPER::_order_directions($order);
}

sub _table {
  my ($self, $from) = @_;
  if (ref $from eq 'ARRAY') {
    return $self->_recurse_from(@$from);
  } elsif (ref $from eq 'HASH') {
    return $self->_make_as($from);
  } else {
    return $from; # would love to quote here but _table ends up getting called
                  # twice during an ->select without a limit clause due to
                  # the way S::A::Limit->select works. should maybe consider
                  # bypassing this and doing S::A::select($self, ...) in
                  # our select method above. meantime, quoting shims have
                  # been added to select/insert/update/delete here
  }
}

sub _recurse_from {
  my ($self, $from, @join) = @_;
  my @sqlf;
  push(@sqlf, $self->_make_as($from));
  foreach my $j (@join) {
    my ($to, $on) = @$j;

    # check whether a join type exists
    my $join_clause = '';
    my $to_jt = ref($to) eq 'ARRAY' ? $to->[0] : $to;
    if (ref($to_jt) eq 'HASH' and exists($to_jt->{-join_type})) {
      $join_clause = ' '.uc($to_jt->{-join_type}).' JOIN ';
    } else {
      $join_clause = ' JOIN ';
    }
    push(@sqlf, $join_clause);

    if (ref $to eq 'ARRAY') {
      push(@sqlf, '(', $self->_recurse_from(@$to), ')');
    } else {
      push(@sqlf, $self->_make_as($to));
    }
    push(@sqlf, ' ON ', $self->_join_condition($on));
  }
  return join('', @sqlf);
}

sub _make_as {
  my ($self, $from) = @_;
  return join(' ', map { (ref $_ eq 'SCALAR' ? $$_ : $self->_quote($_)) }
                     reverse each %{$self->_skip_options($from)});
}

sub _skip_options {
  my ($self, $hash) = @_;
  my $clean_hash = {};
  $clean_hash->{$_} = $hash->{$_}
    for grep {!/^-/} keys %$hash;
  return $clean_hash;
}

sub _join_condition {
  my ($self, $cond) = @_;
  if (ref $cond eq 'HASH') {
    my %j;
    for (keys %$cond) {
      my $x = '= '.$self->_quote($cond->{$_}); $j{$_} = \$x;
    };
    return $self->_recurse_where(\%j);
  } elsif (ref $cond eq 'ARRAY') {
    return join(' OR ', map { $self->_join_condition($_) } @$cond);
  } else {
    die "Can't handle this yet!";
  }
}

sub _quote {
  my ($self, $label) = @_;
  return '' unless defined $label;
  return "*" if $label eq '*';
  return $label unless $self->{quote_char};
  if(ref $self->{quote_char} eq "ARRAY"){
    return $self->{quote_char}->[0] . $label . $self->{quote_char}->[1]
      if !defined $self->{name_sep};
    my $sep = $self->{name_sep};
    return join($self->{name_sep},
        map { $self->{quote_char}->[0] . $_ . $self->{quote_char}->[1]  }
       split(/\Q$sep\E/,$label));
  }
  return $self->SUPER::_quote($label);
}

sub limit_dialect {
    my $self = shift;
    $self->{limit_dialect} = shift if @_;
    return $self->{limit_dialect};
}

sub quote_char {
    my $self = shift;
    $self->{quote_char} = shift if @_;
    return $self->{quote_char};
}

sub name_sep {
    my $self = shift;
    $self->{name_sep} = shift if @_;
    return $self->{name_sep};
}

} # End of BEGIN block

=head1 NAME

DBIx::Class::Storage::DBI - DBI storage handler

=head1 SYNOPSIS

=head1 DESCRIPTION

This class represents the connection to an RDBMS via L<DBI>.  See
L<DBIx::Class::Storage> for general information.  This pod only
documents DBI-specific methods and behaviors.

=head1 METHODS

=cut

sub new {
  my $new = shift->next::method(@_);

  $new->cursor("DBIx::Class::Storage::DBI::Cursor");
  $new->transaction_depth(0);
  $new->_sql_maker_opts({});
  $new->{_in_dbh_do} = 0;

  $new;
}

=head2 connect_info

The arguments of C<connect_info> are always a single array reference.

This is normally accessed via L<DBIx::Class::Schema/connection>, which
encapsulates its argument list in an arrayref before calling
C<connect_info> here.

The arrayref can either contain the same set of arguments one would
normally pass to L<DBI/connect>, or a lone code reference which returns
a connected database handle.

In either case, if the final argument in your connect_info happens
to be a hashref, C<connect_info> will look there for several
connection-specific options:

=over 4

=item on_connect_do

This can be set to an arrayref of literal sql statements, which will
be executed immediately after making the connection to the database
every time we [re-]connect.

=item limit_dialect 

Sets the limit dialect. This is useful for JDBC-bridge among others
where the remote SQL-dialect cannot be determined by the name of the
driver alone.

=item quote_char

Specifies what characters to use to quote table and column names. If 
you use this you will want to specify L<name_sep> as well.

quote_char expects either a single character, in which case is it is placed
on either side of the table/column, or an arrayref of length 2 in which case the
table/column name is placed between the elements.

For example under MySQL you'd use C<quote_char =E<gt> '`'>, and user SQL Server you'd 
use C<quote_char =E<gt> [qw/[ ]/]>.

=item name_sep

This only needs to be used in conjunction with L<quote_char>, and is used to 
specify the charecter that seperates elements (schemas, tables, columns) from 
each other. In most cases this is simply a C<.>.

=back

These options can be mixed in with your other L<DBI> connection attributes,
or placed in a seperate hashref after all other normal L<DBI> connection
arguments.

Every time C<connect_info> is invoked, any previous settings for
these options will be cleared before setting the new ones, regardless of
whether any options are specified in the new C<connect_info>.

Important note:  DBIC expects the returned database handle provided by 
a subref argument to have RaiseError set on it.  If it doesn't, things
might not work very well, YMMV.  If you don't use a subref, DBIC will
force this setting for you anyways.  Setting HandleError to anything
other than simple exception object wrapper might cause problems too.

Examples:

  # Simple SQLite connection
  ->connect_info([ 'dbi:SQLite:./foo.db' ]);

  # Connect via subref
  ->connect_info([ sub { DBI->connect(...) } ]);

  # A bit more complicated
  ->connect_info(
    [
      'dbi:Pg:dbname=foo',
      'postgres',
      'my_pg_password',
      { AutoCommit => 0 },
      { quote_char => q{"}, name_sep => q{.} },
    ]
  );

  # Equivalent to the previous example
  ->connect_info(
    [
      'dbi:Pg:dbname=foo',
      'postgres',
      'my_pg_password',
      { AutoCommit => 0, quote_char => q{"}, name_sep => q{.} },
    ]
  );

  # Subref + DBIC-specific connection options
  ->connect_info(
    [
      sub { DBI->connect(...) },
      {
          quote_char => q{`},
          name_sep => q{@},
          on_connect_do => ['SET search_path TO myschema,otherschema,public'],
      },
    ]
  );

=cut

sub connect_info {
  my ($self, $info_arg) = @_;

  return $self->_connect_info if !$info_arg;

  # Kill sql_maker/_sql_maker_opts, so we get a fresh one with only
  #  the new set of options
  $self->_sql_maker(undef);
  $self->_sql_maker_opts({});

  my $info = [ @$info_arg ]; # copy because we can alter it
  my $last_info = $info->[-1];
  if(ref $last_info eq 'HASH') {
    if(my $on_connect_do = delete $last_info->{on_connect_do}) {
      $self->on_connect_do($on_connect_do);
    }
    for my $sql_maker_opt (qw/limit_dialect quote_char name_sep/) {
      if(my $opt_val = delete $last_info->{$sql_maker_opt}) {
        $self->_sql_maker_opts->{$sql_maker_opt} = $opt_val;
      }
    }

    # Get rid of any trailing empty hashref
    pop(@$info) if !keys %$last_info;
  }

  $self->_connect_info($info);
}

=head2 on_connect_do

This method is deprecated in favor of setting via L</connect_info>.

=head2 dbh_do

Arguments: $subref, @extra_coderef_args?

Execute the given subref using the new exception-based connection management.

The first two arguments will be the storage object that C<dbh_do> was called
on and a database handle to use.  Any additional arguments will be passed
verbatim to the called subref as arguments 2 and onwards.

Using this (instead of $self->_dbh or $self->dbh) ensures correct
exception handling and reconnection (or failover in future subclasses).

Your subref should have no side-effects outside of the database, as
there is the potential for your subref to be partially double-executed
if the database connection was stale/dysfunctional.

Example:

  my @stuff = $schema->storage->dbh_do(
    sub {
      my ($storage, $dbh, @cols) = @_;
      my $cols = join(q{, }, @cols);
      $dbh->selectrow_array("SELECT $cols FROM foo");
    },
    @column_list
  );

=cut

sub dbh_do {
  my $self = shift;
  my $coderef = shift;

  ref $coderef eq 'CODE' or $self->throw_exception
    ('$coderef must be a CODE reference');

  return $coderef->($self, $self->_dbh, @_) if $self->{_in_dbh_do};
  local $self->{_in_dbh_do} = 1;

  my @result;
  my $want_array = wantarray;

  eval {
    $self->_verify_pid if $self->_dbh;
    $self->_populate_dbh if !$self->_dbh;
    if($want_array) {
        @result = $coderef->($self, $self->_dbh, @_);
    }
    elsif(defined $want_array) {
        $result[0] = $coderef->($self, $self->_dbh, @_);
    }
    else {
        $coderef->($self, $self->_dbh, @_);
    }
  };

  my $exception = $@;
  if(!$exception) { return $want_array ? @result : $result[0] }

  $self->throw_exception($exception) if $self->connected;

  # We were not connected - reconnect and retry, but let any
  #  exception fall right through this time
  $self->_populate_dbh;
  $coderef->($self, $self->_dbh, @_);
}

# This is basically a blend of dbh_do above and DBIx::Class::Storage::txn_do.
# It also informs dbh_do to bypass itself while under the direction of txn_do,
#  via $self->{_in_dbh_do} (this saves some redundant eval and errorcheck, etc)
sub txn_do {
  my $self = shift;
  my $coderef = shift;

  ref $coderef eq 'CODE' or $self->throw_exception
    ('$coderef must be a CODE reference');

  local $self->{_in_dbh_do} = 1;

  my @result;
  my $want_array = wantarray;

  my $tried = 0;
  while(1) {
    eval {
      $self->_verify_pid if $self->_dbh;
      $self->_populate_dbh if !$self->_dbh;

      $self->txn_begin;
      if($want_array) {
          @result = $coderef->(@_);
      }
      elsif(defined $want_array) {
          $result[0] = $coderef->(@_);
      }
      else {
          $coderef->(@_);
      }
      $self->txn_commit;
    };

    my $exception = $@;
    if(!$exception) { return $want_array ? @result : $result[0] }

    if($tried++ > 0 || $self->connected) {
      eval { $self->txn_rollback };
      my $rollback_exception = $@;
      if($rollback_exception) {
        my $exception_class = "DBIx::Class::Storage::NESTED_ROLLBACK_EXCEPTION";
        $self->throw_exception($exception)  # propagate nested rollback
          if $rollback_exception =~ /$exception_class/;

        $self->throw_exception(
          "Transaction aborted: ${exception}. "
          . "Rollback failed: ${rollback_exception}"
        );
      }
      $self->throw_exception($exception)
    }

    # We were not connected, and was first try - reconnect and retry
    # via the while loop
    $self->_populate_dbh;
  }
}

=head2 disconnect

Our C<disconnect> method also performs a rollback first if the
database is not in C<AutoCommit> mode.

=cut

sub disconnect {
  my ($self) = @_;

  if( $self->connected ) {
    $self->_dbh->rollback unless $self->_dbh->{AutoCommit};
    $self->_dbh->disconnect;
    $self->_dbh(undef);
  }
}

sub connected {
  my ($self) = @_;

  if(my $dbh = $self->_dbh) {
      if(defined $self->_conn_tid && $self->_conn_tid != threads->tid) {
          return $self->_dbh(undef);
      }
      else {
          $self->_verify_pid;
      }
      return ($dbh->FETCH('Active') && $dbh->ping);
  }

  return 0;
}

# handle pid changes correctly
#  NOTE: assumes $self->_dbh is a valid $dbh
sub _verify_pid {
  my ($self) = @_;

  return if $self->_conn_pid == $$;

  $self->_dbh->{InactiveDestroy} = 1;
  $self->_dbh(undef);

  return;
}

sub ensure_connected {
  my ($self) = @_;

  unless ($self->connected) {
    $self->_populate_dbh;
  }
}

=head2 dbh

Returns the dbh - a data base handle of class L<DBI>.

=cut

sub dbh {
  my ($self) = @_;

  $self->ensure_connected;
  return $self->_dbh;
}

sub _sql_maker_args {
    my ($self) = @_;
    
    return ( limit_dialect => $self->dbh, %{$self->_sql_maker_opts} );
}

sub sql_maker {
  my ($self) = @_;
  unless ($self->_sql_maker) {
    $self->_sql_maker(new DBIC::SQL::Abstract( $self->_sql_maker_args ));
  }
  return $self->_sql_maker;
}

sub _populate_dbh {
  my ($self) = @_;
  my @info = @{$self->_connect_info || []};
  $self->_dbh($self->_connect(@info));

  if(ref $self eq 'DBIx::Class::Storage::DBI') {
    my $driver = $self->_dbh->{Driver}->{Name};
    if ($self->load_optional_class("DBIx::Class::Storage::DBI::${driver}")) {
      bless $self, "DBIx::Class::Storage::DBI::${driver}";
      $self->_rebless() if $self->can('_rebless');
    }
  }

  # if on-connect sql statements are given execute them
  foreach my $sql_statement (@{$self->on_connect_do || []}) {
    $self->debugobj->query_start($sql_statement) if $self->debug();
    $self->_dbh->do($sql_statement);
    $self->debugobj->query_end($sql_statement) if $self->debug();
  }

  $self->_conn_pid($$);
  $self->_conn_tid(threads->tid) if $INC{'threads.pm'};
}

sub _connect {
  my ($self, @info) = @_;

  $self->throw_exception("You failed to provide any connection info")
      if !@info;

  my ($old_connect_via, $dbh);

  if ($INC{'Apache/DBI.pm'} && $ENV{MOD_PERL}) {
      $old_connect_via = $DBI::connect_via;
      $DBI::connect_via = 'connect';
  }

  eval {
    if(ref $info[0] eq 'CODE') {
       $dbh = &{$info[0]}
    }
    else {
       $dbh = DBI->connect(@info);
       $dbh->{RaiseError} = 1;
       $dbh->{PrintError} = 0;
       $dbh->{PrintWarn} = 0;
    }
  };

  $DBI::connect_via = $old_connect_via if $old_connect_via;

  if (!$dbh || $@) {
    $self->throw_exception("DBI Connection failed: " . ($@ || $DBI::errstr));
  }

  $dbh;
}

sub _dbh_txn_begin {
  my ($self, $dbh) = @_;
  if ($dbh->{AutoCommit}) {
    $self->debugobj->txn_begin()
      if ($self->debug);
    $dbh->begin_work;
  }
}

sub txn_begin {
  my $self = shift;
  $self->dbh_do($self->can('_dbh_txn_begin'))
    if $self->{transaction_depth}++ == 0;
}

sub _dbh_txn_commit {
  my ($self, $dbh) = @_;
  if ($self->{transaction_depth} == 0) {
    unless ($dbh->{AutoCommit}) {
      $self->debugobj->txn_commit()
        if ($self->debug);
      $dbh->commit;
    }
  }
  else {
    if (--$self->{transaction_depth} == 0) {
      $self->debugobj->txn_commit()
        if ($self->debug);
      $dbh->commit;
    }
  }
}

sub txn_commit {
  my $self = shift;
  $self->dbh_do($self->can('_dbh_txn_commit'));
}

sub _dbh_txn_rollback {
  my ($self, $dbh) = @_;
  if ($self->{transaction_depth} == 0) {
    unless ($dbh->{AutoCommit}) {
      $self->debugobj->txn_rollback()
        if ($self->debug);
      $dbh->rollback;
    }
  }
  else {
    if (--$self->{transaction_depth} == 0) {
      $self->debugobj->txn_rollback()
        if ($self->debug);
      $dbh->rollback;
    }
    else {
      die DBIx::Class::Storage::NESTED_ROLLBACK_EXCEPTION->new;
    }
  }
}

sub txn_rollback {
  my $self = shift;

  eval { $self->dbh_do($self->can('_dbh_txn_rollback')) };
  if ($@) {
    my $error = $@;
    my $exception_class = "DBIx::Class::Storage::NESTED_ROLLBACK_EXCEPTION";
    $error =~ /$exception_class/ and $self->throw_exception($error);
    $self->{transaction_depth} = 0;          # ensure that a failed rollback
    $self->throw_exception($error);          # resets the transaction depth
  }
}

# This used to be the top-half of _execute.  It was split out to make it
#  easier to override in NoBindVars without duping the rest.  It takes up
#  all of _execute's args, and emits $sql, @bind.
sub _prep_for_execute {
  my ($self, $op, $extra_bind, $ident, @args) = @_;

  my ($sql, @bind) = $self->sql_maker->$op($ident, @args);
  unshift(@bind, @$extra_bind) if $extra_bind;
  @bind = map { ref $_ ? ''.$_ : $_ } @bind; # stringify args

  return ($sql, @bind);
}

sub _execute {
  my $self = shift;

  my ($sql, @bind) = $self->_prep_for_execute(@_);

  if ($self->debug) {
      my @debug_bind = map { defined $_ ? qq{'$_'} : q{'NULL'} } @bind;
      $self->debugobj->query_start($sql, @debug_bind);
  }

  my $sth = $self->sth($sql);

  my $rv;
  if ($sth) {
    my $time = time();
    $rv = eval { $sth->execute(@bind) };

    if ($@ || !$rv) {
      $self->throw_exception("Error executing '$sql': ".($@ || $sth->errstr));
    }
  } else {
    $self->throw_exception("'$sql' did not generate a statement.");
  }
  if ($self->debug) {
      my @debug_bind = map { defined $_ ? qq{`$_'} : q{`NULL'} } @bind;
      $self->debugobj->query_end($sql, @debug_bind);
  }
  return (wantarray ? ($rv, $sth, @bind) : $rv);
}

sub insert {
  my ($self, $ident, $to_insert) = @_;
  $self->throw_exception(
    "Couldn't insert ".join(', ',
      map "$_ => $to_insert->{$_}", keys %$to_insert
    )." into ${ident}"
  ) unless ($self->_execute('insert' => [], $ident, $to_insert));
  return $to_insert;
}

sub update {
  return shift->_execute('update' => [], @_);
}

sub delete {
  return shift->_execute('delete' => [], @_);
}

sub _select {
  my ($self, $ident, $select, $condition, $attrs) = @_;
  my $order = $attrs->{order_by};
  if (ref $condition eq 'SCALAR') {
    $order = $1 if $$condition =~ s/ORDER BY (.*)$//i;
  }
  if (exists $attrs->{group_by} || $attrs->{having}) {
    $order = {
      group_by => $attrs->{group_by},
      having => $attrs->{having},
      ($order ? (order_by => $order) : ())
    };
  }
  my @args = ('select', $attrs->{bind}, $ident, $select, $condition, $order);
  if ($attrs->{software_limit} ||
      $self->sql_maker->_default_limit_syntax eq "GenericSubQ") {
        $attrs->{software_limit} = 1;
  } else {
    $self->throw_exception("rows attribute must be positive if present")
      if (defined($attrs->{rows}) && !($attrs->{rows} > 0));
    push @args, $attrs->{rows}, $attrs->{offset};
  }
  return $self->_execute(@args);
}

=head2 select

=over 4

=item Arguments: $ident, $select, $condition, $attrs

=back

Handle a SQL select statement.

=cut

sub select {
  my $self = shift;
  my ($ident, $select, $condition, $attrs) = @_;
  return $self->cursor->new($self, \@_, $attrs);
}

sub select_single {
  my $self = shift;
  my ($rv, $sth, @bind) = $self->_select(@_);
  my @row = $sth->fetchrow_array;
  # Need to call finish() to work round broken DBDs
  $sth->finish();
  return @row;
}

=head2 sth

=over 4

=item Arguments: $sql

=back

Returns a L<DBI> sth (statement handle) for the supplied SQL.

=cut

sub _dbh_sth {
  my ($self, $dbh, $sql) = @_;
  # 3 is the if_active parameter which avoids active sth re-use
  $dbh->prepare_cached($sql, {}, 3) or
    $self->throw_exception(
      'no sth generated via sql (' . ($@ || $dbh->errstr) . "): $sql"
    );
}

sub sth {
  my ($self, $sql) = @_;
  $self->dbh_do($self->can('_dbh_sth'), $sql);
}

sub _dbh_columns_info_for {
  my ($self, $dbh, $table) = @_;

  if ($dbh->can('column_info')) {
    my %result;
    eval {
      my ($schema,$tab) = $table =~ /^(.+?)\.(.+)$/ ? ($1,$2) : (undef,$table);
      my $sth = $dbh->column_info( undef,$schema, $tab, '%' );
      $sth->execute();
      while ( my $info = $sth->fetchrow_hashref() ){
        my %column_info;
        $column_info{data_type}   = $info->{TYPE_NAME};
        $column_info{size}      = $info->{COLUMN_SIZE};
        $column_info{is_nullable}   = $info->{NULLABLE} ? 1 : 0;
        $column_info{default_value} = $info->{COLUMN_DEF};
        my $col_name = $info->{COLUMN_NAME};
        $col_name =~ s/^\"(.*)\"$/$1/;

        $result{$col_name} = \%column_info;
      }
    };
    return \%result if !$@ && scalar keys %result;
  }

  my %result;
  my $sth = $dbh->prepare("SELECT * FROM $table WHERE 1=0");
  $sth->execute;
  my @columns = @{$sth->{NAME_lc}};
  for my $i ( 0 .. $#columns ){
    my %column_info;
    my $type_num = $sth->{TYPE}->[$i];
    my $type_name;
    if(defined $type_num && $dbh->can('type_info')) {
      my $type_info = $dbh->type_info($type_num);
      $type_name = $type_info->{TYPE_NAME} if $type_info;
    }
    $column_info{data_type} = $type_name ? $type_name : $type_num;
    $column_info{size} = $sth->{PRECISION}->[$i];
    $column_info{is_nullable} = $sth->{NULLABLE}->[$i] ? 1 : 0;

    if ($column_info{data_type} =~ m/^(.*?)\((.*?)\)$/) {
      $column_info{data_type} = $1;
      $column_info{size}    = $2;
    }

    $result{$columns[$i]} = \%column_info;
  }

  return \%result;
}

sub columns_info_for {
  my ($self, $table) = @_;
  $self->dbh_do($self->can('_dbh_columns_info_for'), $table);
}

=head2 last_insert_id

Return the row id of the last insert.

=cut

sub _dbh_last_insert_id {
    my ($self, $dbh, $source, $col) = @_;
    # XXX This is a SQLite-ism as a default... is there a DBI-generic way?
    $dbh->func('last_insert_rowid');
}

sub last_insert_id {
  my $self = shift;
  $self->dbh_do($self->can('_dbh_last_insert_id'), @_);
}

=head2 sqlt_type

Returns the database driver name.

=cut

sub sqlt_type { shift->dbh->{Driver}->{Name} }

=head2 create_ddl_dir (EXPERIMENTAL)

=over 4

=item Arguments: $schema \@databases, $version, $directory, $sqlt_args

=back

Creates a SQL file based on the Schema, for each of the specified
database types, in the given directory.

Note that this feature is currently EXPERIMENTAL and may not work correctly
across all databases, or fully handle complex relationships.

=cut

sub create_ddl_dir
{
  my ($self, $schema, $databases, $version, $dir, $sqltargs) = @_;

  if(!$dir || !-d $dir)
  {
    warn "No directory given, using ./\n";
    $dir = "./";
  }
  $databases ||= ['MySQL', 'SQLite', 'PostgreSQL'];
  $databases = [ $databases ] if(ref($databases) ne 'ARRAY');
  $version ||= $schema->VERSION || '1.x';
  $sqltargs = { ( add_drop_table => 1 ), %{$sqltargs || {}} };

  eval "use SQL::Translator";
  $self->throw_exception("Can't deploy without SQL::Translator: $@") if $@;

  my $sqlt = SQL::Translator->new($sqltargs);
  foreach my $db (@$databases)
  {
    $sqlt->reset();
    $sqlt->parser('SQL::Translator::Parser::DBIx::Class');
#    $sqlt->parser_args({'DBIx::Class' => $schema);
    $sqlt->data($schema);
    $sqlt->producer($db);

    my $file;
    my $filename = $schema->ddl_filename($db, $dir, $version);
    if(-e $filename)
    {
      $self->throw_exception("$filename already exists, skipping $db");
      next;
    }
    open($file, ">$filename") 
      or $self->throw_exception("Can't open $filename for writing ($!)");
    my $output = $sqlt->translate;
#use Data::Dumper;
#    print join(":", keys %{$schema->source_registrations});
#    print Dumper($sqlt->schema);
    if(!$output)
    {
      $self->throw_exception("Failed to translate to $db. (" . $sqlt->error . ")");
      next;
    }
    print $file $output;
    close($file);
  }

}

=head2 deployment_statements

=over 4

=item Arguments: $schema, $type, $version, $directory, $sqlt_args

=back

Returns the statements used by L</deploy> and L<DBIx::Class::Schema/deploy>.
The database driver name is given by C<$type>, though the value from
L</sqlt_type> is used if it is not specified.

C<$directory> is used to return statements from files in a previously created
L</create_ddl_dir> directory and is optional. The filenames are constructed
from L<DBIx::Class::Schema/ddl_filename>, the schema name and the C<$version>.

If no C<$directory> is specified then the statements are constructed on the
fly using L<SQL::Translator> and C<$version> is ignored.

See L<SQL::Translator/METHODS> for a list of values for C<$sqlt_args>.

=cut

sub deployment_statements {
  my ($self, $schema, $type, $version, $dir, $sqltargs) = @_;
  # Need to be connected to get the correct sqlt_type
  $self->ensure_connected() unless $type;
  $type ||= $self->sqlt_type;
  $version ||= $schema->VERSION || '1.x';
  $dir ||= './';
  eval "use SQL::Translator";
  if(!$@)
  {
    eval "use SQL::Translator::Parser::DBIx::Class;";
    $self->throw_exception($@) if $@;
    eval "use SQL::Translator::Producer::${type};";
    $self->throw_exception($@) if $@;
    my $tr = SQL::Translator->new(%$sqltargs);
    SQL::Translator::Parser::DBIx::Class::parse( $tr, $schema );
    return "SQL::Translator::Producer::${type}"->can('produce')->($tr);
  }

  my $filename = $schema->ddl_filename($type, $dir, $version);
  if(!-f $filename)
  {
#      $schema->create_ddl_dir([ $type ], $version, $dir, $sqltargs);
      $self->throw_exception("No SQL::Translator, and no Schema file found, aborting deploy");
      return;
  }
  my $file;
  open($file, "<$filename") 
      or $self->throw_exception("Can't open $filename ($!)");
  my @rows = <$file>;
  close($file);

  return join('', @rows);
  
}

sub deploy {
  my ($self, $schema, $type, $sqltargs, $dir) = @_;
  foreach my $statement ( $self->deployment_statements($schema, $type, undef, $dir, { no_comments => 1, %{ $sqltargs || {} } } ) ) {
    for ( split(";\n", $statement)) {
      next if($_ =~ /^--/);
      next if(!$_);
#      next if($_ =~ /^DROP/m);
      next if($_ =~ /^BEGIN TRANSACTION/m);
      next if($_ =~ /^COMMIT/m);
      next if $_ =~ /^\s+$/; # skip whitespace only
      $self->debugobj->query_start($_) if $self->debug;
      $self->dbh->do($_) or warn "SQL was:\n $_"; # XXX exceptions?
      $self->debugobj->query_end($_) if $self->debug;
    }
  }
}

=head2 datetime_parser

Returns the datetime parser class

=cut

sub datetime_parser {
  my $self = shift;
  return $self->{datetime_parser} ||= $self->build_datetime_parser(@_);
}

=head2 datetime_parser_type

Defines (returns) the datetime parser class - currently hardwired to
L<DateTime::Format::MySQL>

=cut

sub datetime_parser_type { "DateTime::Format::MySQL"; }

=head2 build_datetime_parser

See L</datetime_parser>

=cut

sub build_datetime_parser {
  my $self = shift;
  my $type = $self->datetime_parser_type(@_);
  eval "use ${type}";
  $self->throw_exception("Couldn't load ${type}: $@") if $@;
  return $type;
}

sub DESTROY {
  my $self = shift;
  return if !$self->_dbh;
  $self->_verify_pid;
  $self->_dbh(undef);
}

1;

=head1 SQL METHODS

The module defines a set of methods within the DBIC::SQL::Abstract
namespace.  These build on L<SQL::Abstract::Limit> to provide the
SQL query functions.

The following methods are extended:-

=over 4

=item delete

=item insert

=item select

=item update

=item limit_dialect

See L</connect_info> for details.
For setting, this method is deprecated in favor of L</connect_info>.

=item quote_char

See L</connect_info> for details.
For setting, this method is deprecated in favor of L</connect_info>.

=item name_sep

See L</connect_info> for details.
For setting, this method is deprecated in favor of L</connect_info>.

=back

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

Andy Grundman <andy@hybridized.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
