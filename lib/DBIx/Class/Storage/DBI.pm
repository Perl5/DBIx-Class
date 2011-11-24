package DBIx::Class::Storage::DBI;
# -*- mode: cperl; cperl-indent-level: 2 -*-

use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBIHacks DBIx::Class::Storage/;
use mro 'c3';

use DBIx::Class::Carp;
use DBIx::Class::Exception;
use Scalar::Util qw/refaddr weaken reftype blessed/;
use List::Util qw/first/;
use Sub::Name 'subname';
use Try::Tiny;
use overload ();
use namespace::clean;

# default cursor class, overridable in connect_info attributes
__PACKAGE__->cursor_class('DBIx::Class::Storage::DBI::Cursor');

__PACKAGE__->mk_group_accessors('inherited' => qw/
  sql_limit_dialect sql_quote_char sql_name_sep
/);

__PACKAGE__->mk_group_accessors('component_class' => qw/sql_maker_class datetime_parser_type/);

__PACKAGE__->sql_maker_class('DBIx::Class::SQLMaker');
__PACKAGE__->datetime_parser_type('DateTime::Format::MySQL'); # historic default

__PACKAGE__->sql_name_sep('.');

__PACKAGE__->mk_group_accessors('simple' => qw/
  _connect_info _dbi_connect_info _dbic_connect_attributes _driver_determined
  _dbh _dbh_details _conn_pid _sql_maker _sql_maker_opts _dbh_autocommit
/);

# the values for these accessors are picked out (and deleted) from
# the attribute hashref passed to connect_info
my @storage_options = qw/
  on_connect_call on_disconnect_call on_connect_do on_disconnect_do
  disable_sth_caching unsafe auto_savepoint
/;
__PACKAGE__->mk_group_accessors('simple' => @storage_options);


# capability definitions, using a 2-tiered accessor system
# The rationale is:
#
# A driver/user may define _use_X, which blindly without any checks says:
# "(do not) use this capability", (use_dbms_capability is an "inherited"
# type accessor)
#
# If _use_X is undef, _supports_X is then queried. This is a "simple" style
# accessor, which in turn calls _determine_supports_X, and stores the return
# in a special slot on the storage object, which is wiped every time a $dbh
# reconnection takes place (it is not guaranteed that upon reconnection we
# will get the same rdbms version). _determine_supports_X does not need to
# exist on a driver, as we ->can for it before calling.

my @capabilities = (qw/
  insert_returning
  insert_returning_bound
  placeholders
  typeless_placeholders
  join_optimizer
/);
__PACKAGE__->mk_group_accessors( dbms_capability => map { "_supports_$_" } @capabilities );
__PACKAGE__->mk_group_accessors( use_dbms_capability => map { "_use_$_" } (@capabilities ) );

# on by default, not strictly a capability (pending rewrite)
__PACKAGE__->_use_join_optimizer (1);
sub _determine_supports_join_optimizer { 1 };

# Each of these methods need _determine_driver called before itself
# in order to function reliably. This is a purely DRY optimization
#
# get_(use)_dbms_capability need to be called on the correct Storage
# class, as _use_X may be hardcoded class-wide, and _supports_X calls
# _determine_supports_X which obv. needs a correct driver as well
my @rdbms_specific_methods = qw/
  deployment_statements
  sqlt_type
  sql_maker
  build_datetime_parser
  datetime_parser_type

  txn_begin
  insert
  insert_bulk
  update
  delete
  select
  select_single
  with_deferred_fk_checks

  get_use_dbms_capability
  get_dbms_capability

  _server_info
  _get_server_version
/;

for my $meth (@rdbms_specific_methods) {

  my $orig = __PACKAGE__->can ($meth)
    or die "$meth is not a ::Storage::DBI method!";

  no strict qw/refs/;
  no warnings qw/redefine/;
  *{__PACKAGE__ ."::$meth"} = subname $meth => sub {
    if (
      # only fire when invoked on an instance, a valid class-based invocation
      # would e.g. be setting a default for an inherited accessor
      ref $_[0]
        and
      ! $_[0]->_driver_determined
        and
      ! $_[0]->{_in_determine_driver}
    ) {
      $_[0]->_determine_driver;

      # This for some reason crashes and burns on perl 5.8.1
      # IFF the method ends up throwing an exception
      #goto $_[0]->can ($meth);

      my $cref = $_[0]->can ($meth);
      goto $cref;
    }

    goto $orig;
  };
}

=head1 NAME

DBIx::Class::Storage::DBI - DBI storage handler

=head1 SYNOPSIS

  my $schema = MySchema->connect('dbi:SQLite:my.db');

  $schema->storage->debug(1);

  my @stuff = $schema->storage->dbh_do(
    sub {
      my ($storage, $dbh, @args) = @_;
      $dbh->do("DROP TABLE authors");
    },
    @column_list
  );

  $schema->resultset('Book')->search({
     written_on => $schema->storage->datetime_parser->format_datetime(DateTime->now)
  });

=head1 DESCRIPTION

This class represents the connection to an RDBMS via L<DBI>.  See
L<DBIx::Class::Storage> for general information.  This pod only
documents DBI-specific methods and behaviors.

=head1 METHODS

=cut

sub new {
  my $new = shift->next::method(@_);

  $new->_sql_maker_opts({});
  $new->_dbh_details({});
  $new->{_in_do_block} = 0;
  $new->{_dbh_gen} = 0;

  # read below to see what this does
  $new->_arm_global_destructor;

  $new;
}

# This is hack to work around perl shooting stuff in random
# order on exit(). If we do not walk the remaining storage
# objects in an END block, there is a *small but real* chance
# of a fork()ed child to kill the parent's shared DBI handle,
# *before perl reaches the DESTROY in this package*
# Yes, it is ugly and effective.
# Additionally this registry is used by the CLONE method to
# make sure no handles are shared between threads
{
  my %seek_and_destroy;

  sub _arm_global_destructor {
    my $self = shift;
    my $key = refaddr ($self);
    $seek_and_destroy{$key} = $self;
    weaken ($seek_and_destroy{$key});
  }

  END {
    local $?; # just in case the DBI destructor changes it somehow

    # destroy just the object if not native to this process/thread
    $_->_verify_pid for (grep
      { defined $_ }
      values %seek_and_destroy
    );
  }

  sub CLONE {
    # As per DBI's recommendation, DBIC disconnects all handles as
    # soon as possible (DBIC will reconnect only on demand from within
    # the thread)
    for (values %seek_and_destroy) {
      next unless $_;
      $_->{_dbh_gen}++;  # so that existing cursors will drop as well
      $_->_dbh(undef);

      $_->transaction_depth(0);
      $_->savepoints([]);
    }
  }
}

sub DESTROY {
  my $self = shift;

  # some databases spew warnings on implicit disconnect
  local $SIG{__WARN__} = sub {};
  $self->_dbh(undef);

  # this op is necessary, since the very last perl runtime statement
  # triggers a global destruction shootout, and the $SIG localization
  # may very well be destroyed before perl actually gets to do the
  # $dbh undef
  1;
}

# handle pid changes correctly - do not destroy parent's connection
sub _verify_pid {
  my $self = shift;

  my $pid = $self->_conn_pid;
  if( defined $pid and $pid != $$ and my $dbh = $self->_dbh ) {
    $dbh->{InactiveDestroy} = 1;
    $self->{_dbh_gen}++;
    $self->_dbh(undef);
    $self->transaction_depth(0);
    $self->savepoints([]);
  }

  return;
}

=head2 connect_info

This method is normally called by L<DBIx::Class::Schema/connection>, which
encapsulates its argument list in an arrayref before passing them here.

The argument list may contain:

=over

=item *

The same 4-element argument set one would normally pass to
L<DBI/connect>, optionally followed by
L<extra attributes|/DBIx::Class specific connection attributes>
recognized by DBIx::Class:

  $connect_info_args = [ $dsn, $user, $password, \%dbi_attributes?, \%extra_attributes? ];

=item *

A single code reference which returns a connected
L<DBI database handle|DBI/connect> optionally followed by
L<extra attributes|/DBIx::Class specific connection attributes> recognized
by DBIx::Class:

  $connect_info_args = [ sub { DBI->connect (...) }, \%extra_attributes? ];

=item *

A single hashref with all the attributes and the dsn/user/password
mixed together:

  $connect_info_args = [{
    dsn => $dsn,
    user => $user,
    password => $pass,
    %dbi_attributes,
    %extra_attributes,
  }];

  $connect_info_args = [{
    dbh_maker => sub { DBI->connect (...) },
    %dbi_attributes,
    %extra_attributes,
  }];

This is particularly useful for L<Catalyst> based applications, allowing the
following config (L<Config::General> style):

  <Model::DB>
    schema_class   App::DB
    <connect_info>
      dsn          dbi:mysql:database=test
      user         testuser
      password     TestPass
      AutoCommit   1
    </connect_info>
  </Model::DB>

The C<dsn>/C<user>/C<password> combination can be substituted by the
C<dbh_maker> key whose value is a coderef that returns a connected
L<DBI database handle|DBI/connect>

=back

Please note that the L<DBI> docs recommend that you always explicitly
set C<AutoCommit> to either I<0> or I<1>.  L<DBIx::Class> further
recommends that it be set to I<1>, and that you perform transactions
via our L<DBIx::Class::Schema/txn_do> method.  L<DBIx::Class> will set it
to I<1> if you do not do explicitly set it to zero.  This is the default
for most DBDs. See L</DBIx::Class and AutoCommit> for details.

=head3 DBIx::Class specific connection attributes

In addition to the standard L<DBI|DBI/ATTRIBUTES_COMMON_TO_ALL_HANDLES>
L<connection|DBI/Database_Handle_Attributes> attributes, DBIx::Class recognizes
the following connection options. These options can be mixed in with your other
L<DBI> connection attributes, or placed in a separate hashref
(C<\%extra_attributes>) as shown above.

Every time C<connect_info> is invoked, any previous settings for
these options will be cleared before setting the new ones, regardless of
whether any options are specified in the new C<connect_info>.


=over

=item on_connect_do

Specifies things to do immediately after connecting or re-connecting to
the database.  Its value may contain:

=over

=item a scalar

This contains one SQL statement to execute.

=item an array reference

This contains SQL statements to execute in order.  Each element contains
a string or a code reference that returns a string.

=item a code reference

This contains some code to execute.  Unlike code references within an
array reference, its return value is ignored.

=back

=item on_disconnect_do

Takes arguments in the same form as L</on_connect_do> and executes them
immediately before disconnecting from the database.

Note, this only runs if you explicitly call L</disconnect> on the
storage object.

=item on_connect_call

A more generalized form of L</on_connect_do> that calls the specified
C<connect_call_METHOD> methods in your storage driver.

  on_connect_do => 'select 1'

is equivalent to:

  on_connect_call => [ [ do_sql => 'select 1' ] ]

Its values may contain:

=over

=item a scalar

Will call the C<connect_call_METHOD> method.

=item a code reference

Will execute C<< $code->($storage) >>

=item an array reference

Each value can be a method name or code reference.

=item an array of arrays

For each array, the first item is taken to be the C<connect_call_> method name
or code reference, and the rest are parameters to it.

=back

Some predefined storage methods you may use:

=over

=item do_sql

Executes a SQL string or a code reference that returns a SQL string. This is
what L</on_connect_do> and L</on_disconnect_do> use.

It can take:

=over

=item a scalar

Will execute the scalar as SQL.

=item an arrayref

Taken to be arguments to L<DBI/do>, the SQL string optionally followed by the
attributes hashref and bind values.

=item a code reference

Will execute C<< $code->($storage) >> and execute the return array refs as
above.

=back

=item datetime_setup

Execute any statements necessary to initialize the database session to return
and accept datetime/timestamp values used with
L<DBIx::Class::InflateColumn::DateTime>.

Only necessary for some databases, see your specific storage driver for
implementation details.

=back

=item on_disconnect_call

Takes arguments in the same form as L</on_connect_call> and executes them
immediately before disconnecting from the database.

Calls the C<disconnect_call_METHOD> methods as opposed to the
C<connect_call_METHOD> methods called by L</on_connect_call>.

Note, this only runs if you explicitly call L</disconnect> on the
storage object.

=item disable_sth_caching

If set to a true value, this option will disable the caching of
statement handles via L<DBI/prepare_cached>.

=item limit_dialect

Sets a specific SQL::Abstract::Limit-style limit dialect, overriding the
default L</sql_limit_dialect> setting of the storage (if any). For a list
of available limit dialects see L<DBIx::Class::SQLMaker::LimitDialects>.

=item quote_names

When true automatically sets L</quote_char> and L</name_sep> to the characters
appropriate for your particular RDBMS. This option is preferred over specifying
L</quote_char> directly.

=item quote_char

Specifies what characters to use to quote table and column names.

C<quote_char> expects either a single character, in which case is it
is placed on either side of the table/column name, or an arrayref of length
2 in which case the table/column name is placed between the elements.

For example under MySQL you should use C<< quote_char => '`' >>, and for
SQL Server you should use C<< quote_char => [qw/[ ]/] >>.

=item name_sep

This parameter is only useful in conjunction with C<quote_char>, and is used to
specify the character that separates elements (schemas, tables, columns) from
each other. If unspecified it defaults to the most commonly used C<.>.

=item unsafe

This Storage driver normally installs its own C<HandleError>, sets
C<RaiseError> and C<ShowErrorStatement> on, and sets C<PrintError> off on
all database handles, including those supplied by a coderef.  It does this
so that it can have consistent and useful error behavior.

If you set this option to a true value, Storage will not do its usual
modifications to the database handle's attributes, and instead relies on
the settings in your connect_info DBI options (or the values you set in
your connection coderef, in the case that you are connecting via coderef).

Note that your custom settings can cause Storage to malfunction,
especially if you set a C<HandleError> handler that suppresses exceptions
and/or disable C<RaiseError>.

=item auto_savepoint

If this option is true, L<DBIx::Class> will use savepoints when nesting
transactions, making it possible to recover from failure in the inner
transaction without having to abort all outer transactions.

=item cursor_class

Use this argument to supply a cursor class other than the default
L<DBIx::Class::Storage::DBI::Cursor>.

=back

Some real-life examples of arguments to L</connect_info> and
L<DBIx::Class::Schema/connect>

  # Simple SQLite connection
  ->connect_info([ 'dbi:SQLite:./foo.db' ]);

  # Connect via subref
  ->connect_info([ sub { DBI->connect(...) } ]);

  # Connect via subref in hashref
  ->connect_info([{
    dbh_maker => sub { DBI->connect(...) },
    on_connect_do => 'alter session ...',
  }]);

  # A bit more complicated
  ->connect_info(
    [
      'dbi:Pg:dbname=foo',
      'postgres',
      'my_pg_password',
      { AutoCommit => 1 },
      { quote_char => q{"} },
    ]
  );

  # Equivalent to the previous example
  ->connect_info(
    [
      'dbi:Pg:dbname=foo',
      'postgres',
      'my_pg_password',
      { AutoCommit => 1, quote_char => q{"}, name_sep => q{.} },
    ]
  );

  # Same, but with hashref as argument
  # See parse_connect_info for explanation
  ->connect_info(
    [{
      dsn         => 'dbi:Pg:dbname=foo',
      user        => 'postgres',
      password    => 'my_pg_password',
      AutoCommit  => 1,
      quote_char  => q{"},
      name_sep    => q{.},
    }]
  );

  # Subref + DBIx::Class-specific connection options
  ->connect_info(
    [
      sub { DBI->connect(...) },
      {
          quote_char => q{`},
          name_sep => q{@},
          on_connect_do => ['SET search_path TO myschema,otherschema,public'],
          disable_sth_caching => 1,
      },
    ]
  );



=cut

sub connect_info {
  my ($self, $info) = @_;

  return $self->_connect_info if !$info;

  $self->_connect_info($info); # copy for _connect_info

  $info = $self->_normalize_connect_info($info)
    if ref $info eq 'ARRAY';

  for my $storage_opt (keys %{ $info->{storage_options} }) {
    my $value = $info->{storage_options}{$storage_opt};

    $self->$storage_opt($value);
  }

  # Kill sql_maker/_sql_maker_opts, so we get a fresh one with only
  #  the new set of options
  $self->_sql_maker(undef);
  $self->_sql_maker_opts({});

  for my $sql_maker_opt (keys %{ $info->{sql_maker_options} }) {
    my $value = $info->{sql_maker_options}{$sql_maker_opt};

    $self->_sql_maker_opts->{$sql_maker_opt} = $value;
  }

  my %attrs = (
    %{ $self->_default_dbi_connect_attributes || {} },
    %{ $info->{attributes} || {} },
  );

  my @args = @{ $info->{arguments} };

  if (keys %attrs and ref $args[0] ne 'CODE') {
    carp
        'You provided explicit AutoCommit => 0 in your connection_info. '
      . 'This is almost universally a bad idea (see the footnotes of '
      . 'DBIx::Class::Storage::DBI for more info). If you still want to '
      . 'do this you can set $ENV{DBIC_UNSAFE_AUTOCOMMIT_OK} to disable '
      . 'this warning.'
      if ! $attrs{AutoCommit} and ! $ENV{DBIC_UNSAFE_AUTOCOMMIT_OK};

    push @args, \%attrs if keys %attrs;
  }
  $self->_dbi_connect_info(\@args);

  # FIXME - dirty:
  # save attributes them in a separate accessor so they are always
  # introspectable, even in case of a CODE $dbhmaker
  $self->_dbic_connect_attributes (\%attrs);

  return $self->_connect_info;
}

sub _normalize_connect_info {
  my ($self, $info_arg) = @_;
  my %info;

  my @args = @$info_arg;  # take a shallow copy for further mutilation

  # combine/pre-parse arguments depending on invocation style

  my %attrs;
  if (ref $args[0] eq 'CODE') {     # coderef with optional \%extra_attributes
    %attrs = %{ $args[1] || {} };
    @args = $args[0];
  }
  elsif (ref $args[0] eq 'HASH') { # single hashref (i.e. Catalyst config)
    %attrs = %{$args[0]};
    @args = ();
    if (my $code = delete $attrs{dbh_maker}) {
      @args = $code;

      my @ignored = grep { delete $attrs{$_} } (qw/dsn user password/);
      if (@ignored) {
        carp sprintf (
            'Attribute(s) %s in connect_info were ignored, as they can not be applied '
          . "to the result of 'dbh_maker'",

          join (', ', map { "'$_'" } (@ignored) ),
        );
      }
    }
    else {
      @args = delete @attrs{qw/dsn user password/};
    }
  }
  else {                # otherwise assume dsn/user/password + \%attrs + \%extra_attrs
    %attrs = (
      % { $args[3] || {} },
      % { $args[4] || {} },
    );
    @args = @args[0,1,2];
  }

  $info{arguments} = \@args;

  my @storage_opts = grep exists $attrs{$_},
    @storage_options, 'cursor_class';

  @{ $info{storage_options} }{@storage_opts} =
    delete @attrs{@storage_opts} if @storage_opts;

  my @sql_maker_opts = grep exists $attrs{$_},
    qw/limit_dialect quote_char name_sep quote_names/;

  @{ $info{sql_maker_options} }{@sql_maker_opts} =
    delete @attrs{@sql_maker_opts} if @sql_maker_opts;

  $info{attributes} = \%attrs if %attrs;

  return \%info;
}

sub _default_dbi_connect_attributes () {
  +{
    AutoCommit => 1,
    PrintError => 0,
    RaiseError => 1,
    ShowErrorStatement => 1,
  };
}

=head2 on_connect_do

This method is deprecated in favour of setting via L</connect_info>.

=cut

=head2 on_disconnect_do

This method is deprecated in favour of setting via L</connect_info>.

=cut

sub _parse_connect_do {
  my ($self, $type) = @_;

  my $val = $self->$type;
  return () if not defined $val;

  my @res;

  if (not ref($val)) {
    push @res, [ 'do_sql', $val ];
  } elsif (ref($val) eq 'CODE') {
    push @res, $val;
  } elsif (ref($val) eq 'ARRAY') {
    push @res, map { [ 'do_sql', $_ ] } @$val;
  } else {
    $self->throw_exception("Invalid type for $type: ".ref($val));
  }

  return \@res;
}

=head2 dbh_do

Arguments: ($subref | $method_name), @extra_coderef_args?

Execute the given $subref or $method_name using the new exception-based
connection management.

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
  my $code = shift;

  my $dbh = $self->_get_dbh;

  return $self->$code($dbh, @_)
    if ( $self->{_in_do_block} || $self->{transaction_depth} );

  local $self->{_in_do_block} = 1;

  # take a ref instead of a copy, to preserve coderef @_ aliasing semantics
  my $args = \@_;

  try {
    $self->$code ($dbh, @$args);
  } catch {
    $self->throw_exception($_) if $self->connected;

    # We were not connected - reconnect and retry, but let any
    #  exception fall right through this time
    carp "Retrying dbh_do($code) after catching disconnected exception: $_"
      if $ENV{DBIC_STORAGE_RETRY_DEBUG};

    $self->_populate_dbh;
    $self->$code($self->_dbh, @$args);
  };
}

sub txn_do {
  # connects or reconnects on pid change, necessary to grab correct txn_depth
  $_[0]->_get_dbh;
  local $_[0]->{_in_do_block} = 1;
  shift->next::method(@_);
}

=head2 disconnect

Our C<disconnect> method also performs a rollback first if the
database is not in C<AutoCommit> mode.

=cut

sub disconnect {
  my ($self) = @_;

  if( $self->_dbh ) {
    my @actions;

    push @actions, ( $self->on_disconnect_call || () );
    push @actions, $self->_parse_connect_do ('on_disconnect_do');

    $self->_do_connection_actions(disconnect_call_ => $_) for @actions;

    # stops the "implicit rollback on disconnect" warning
    $self->_exec_txn_rollback unless $self->_dbh_autocommit;

    %{ $self->_dbh->{CachedKids} } = ();
    $self->_dbh->disconnect;
    $self->_dbh(undef);
    $self->{_dbh_gen}++;
  }
}

=head2 with_deferred_fk_checks

=over 4

=item Arguments: C<$coderef>

=item Return Value: The return value of $coderef

=back

Storage specific method to run the code ref with FK checks deferred or
in MySQL's case disabled entirely.

=cut

# Storage subclasses should override this
sub with_deferred_fk_checks {
  my ($self, $sub) = @_;
  $sub->();
}

=head2 connected

=over

=item Arguments: none

=item Return Value: 1|0

=back

Verifies that the current database handle is active and ready to execute
an SQL statement (e.g. the connection did not get stale, server is still
answering, etc.) This method is used internally by L</dbh>.

=cut

sub connected {
  my $self = shift;
  return 0 unless $self->_seems_connected;

  #be on the safe side
  local $self->_dbh->{RaiseError} = 1;

  return $self->_ping;
}

sub _seems_connected {
  my $self = shift;

  $self->_verify_pid;

  my $dbh = $self->_dbh
    or return 0;

  return $dbh->FETCH('Active');
}

sub _ping {
  my $self = shift;

  my $dbh = $self->_dbh or return 0;

  return $dbh->ping;
}

sub ensure_connected {
  my ($self) = @_;

  unless ($self->connected) {
    $self->_populate_dbh;
  }
}

=head2 dbh

Returns a C<$dbh> - a data base handle of class L<DBI>. The returned handle
is guaranteed to be healthy by implicitly calling L</connected>, and if
necessary performing a reconnection before returning. Keep in mind that this
is very B<expensive> on some database engines. Consider using L</dbh_do>
instead.

=cut

sub dbh {
  my ($self) = @_;

  if (not $self->_dbh) {
    $self->_populate_dbh;
  } else {
    $self->ensure_connected;
  }
  return $self->_dbh;
}

# this is the internal "get dbh or connect (don't check)" method
sub _get_dbh {
  my $self = shift;
  $self->_verify_pid;
  $self->_populate_dbh unless $self->_dbh;
  return $self->_dbh;
}

sub sql_maker {
  my ($self) = @_;
  unless ($self->_sql_maker) {
    my $sql_maker_class = $self->sql_maker_class;

    my %opts = %{$self->_sql_maker_opts||{}};
    my $dialect =
      $opts{limit_dialect}
        ||
      $self->sql_limit_dialect
        ||
      do {
        my $s_class = (ref $self) || $self;
        carp (
          "Your storage class ($s_class) does not set sql_limit_dialect and you "
        . 'have not supplied an explicit limit_dialect in your connection_info. '
        . 'DBIC will attempt to use the GenericSubQ dialect, which works on most '
        . 'databases but can be (and often is) painfully slow. '
        . "Please file an RT ticket against '$s_class' ."
        );

        'GenericSubQ';
      }
    ;

    my ($quote_char, $name_sep);

    if ($opts{quote_names}) {
      $quote_char = (delete $opts{quote_char}) || $self->sql_quote_char || do {
        my $s_class = (ref $self) || $self;
        carp (
          "You requested 'quote_names' but your storage class ($s_class) does "
        . 'not explicitly define a default sql_quote_char and you have not '
        . 'supplied a quote_char as part of your connection_info. DBIC will '
        .q{default to the ANSI SQL standard quote '"', which works most of }
        . "the time. Please file an RT ticket against '$s_class'."
        );

        '"'; # RV
      };

      $name_sep = (delete $opts{name_sep}) || $self->sql_name_sep;
    }

    $self->_sql_maker($sql_maker_class->new(
      bindtype=>'columns',
      array_datatypes => 1,
      limit_dialect => $dialect,
      ($quote_char ? (quote_char => $quote_char) : ()),
      name_sep => ($name_sep || '.'),
      %opts,
    ));
  }
  return $self->_sql_maker;
}

# nothing to do by default
sub _rebless {}
sub _init {}

sub _populate_dbh {
  my ($self) = @_;

  my @info = @{$self->_dbi_connect_info || []};
  $self->_dbh(undef); # in case ->connected failed we might get sent here
  $self->_dbh_details({}); # reset everything we know

  $self->_dbh($self->_connect(@info));

  $self->_conn_pid($$) if $^O ne 'MSWin32'; # on win32 these are in fact threads

  $self->_determine_driver;

  # Always set the transaction depth on connect, since
  #  there is no transaction in progress by definition
  $self->{transaction_depth} = $self->_dbh_autocommit ? 0 : 1;

  $self->_run_connection_actions unless $self->{_in_determine_driver};
}

sub _run_connection_actions {
  my $self = shift;
  my @actions;

  push @actions, ( $self->on_connect_call || () );
  push @actions, $self->_parse_connect_do ('on_connect_do');

  $self->_do_connection_actions(connect_call_ => $_) for @actions;
}



sub set_use_dbms_capability {
  $_[0]->set_inherited ($_[1], $_[2]);
}

sub get_use_dbms_capability {
  my ($self, $capname) = @_;

  my $use = $self->get_inherited ($capname);
  return defined $use
    ? $use
    : do { $capname =~ s/^_use_/_supports_/; $self->get_dbms_capability ($capname) }
  ;
}

sub set_dbms_capability {
  $_[0]->_dbh_details->{capability}{$_[1]} = $_[2];
}

sub get_dbms_capability {
  my ($self, $capname) = @_;

  my $cap = $self->_dbh_details->{capability}{$capname};

  unless (defined $cap) {
    if (my $meth = $self->can ("_determine$capname")) {
      $cap = $self->$meth ? 1 : 0;
    }
    else {
      $cap = 0;
    }

    $self->set_dbms_capability ($capname, $cap);
  }

  return $cap;
}

sub _server_info {
  my $self = shift;

  my $info;
  unless ($info = $self->_dbh_details->{info}) {

    $info = {};

    my $server_version = try { $self->_get_server_version };

    if (defined $server_version) {
      $info->{dbms_version} = $server_version;

      my ($numeric_version) = $server_version =~ /^([\d\.]+)/;
      my @verparts = split (/\./, $numeric_version);
      if (
        @verparts
          &&
        $verparts[0] <= 999
      ) {
        # consider only up to 3 version parts, iff not more than 3 digits
        my @use_parts;
        while (@verparts && @use_parts < 3) {
          my $p = shift @verparts;
          last if $p > 999;
          push @use_parts, $p;
        }
        push @use_parts, 0 while @use_parts < 3;

        $info->{normalized_dbms_version} = sprintf "%d.%03d%03d", @use_parts;
      }
    }

    $self->_dbh_details->{info} = $info;
  }

  return $info;
}

sub _get_server_version {
  shift->_dbh_get_info(18);
}

sub _dbh_get_info {
  my ($self, $info) = @_;

  return try { $self->_get_dbh->get_info($info) } || undef;
}

sub _determine_driver {
  my ($self) = @_;

  if ((not $self->_driver_determined) && (not $self->{_in_determine_driver})) {
    my $started_connected = 0;
    local $self->{_in_determine_driver} = 1;

    if (ref($self) eq __PACKAGE__) {
      my $driver;
      if ($self->_dbh) { # we are connected
        $driver = $self->_dbh->{Driver}{Name};
        $started_connected = 1;
      } else {
        # if connect_info is a CODEREF, we have no choice but to connect
        if (ref $self->_dbi_connect_info->[0] &&
            reftype $self->_dbi_connect_info->[0] eq 'CODE') {
          $self->_populate_dbh;
          $driver = $self->_dbh->{Driver}{Name};
        }
        else {
          # try to use dsn to not require being connected, the driver may still
          # force a connection in _rebless to determine version
          # (dsn may not be supplied at all if all we do is make a mock-schema)
          my $dsn = $self->_dbi_connect_info->[0] || $ENV{DBI_DSN} || '';
          ($driver) = $dsn =~ /dbi:([^:]+):/i;
          $driver ||= $ENV{DBI_DRIVER};
        }
      }

      if ($driver) {
        my $storage_class = "DBIx::Class::Storage::DBI::${driver}";
        if ($self->load_optional_class($storage_class)) {
          mro::set_mro($storage_class, 'c3');
          bless $self, $storage_class;
          $self->_rebless();
        }
      }
    }

    $self->_driver_determined(1);

    Class::C3->reinitialize() if DBIx::Class::_ENV_::OLD_MRO;

    $self->_init; # run driver-specific initializations

    $self->_run_connection_actions
        if !$started_connected && defined $self->_dbh;
  }
}

sub _do_connection_actions {
  my $self          = shift;
  my $method_prefix = shift;
  my $call          = shift;

  if (not ref($call)) {
    my $method = $method_prefix . $call;
    $self->$method(@_);
  } elsif (ref($call) eq 'CODE') {
    $self->$call(@_);
  } elsif (ref($call) eq 'ARRAY') {
    if (ref($call->[0]) ne 'ARRAY') {
      $self->_do_connection_actions($method_prefix, $_) for @$call;
    } else {
      $self->_do_connection_actions($method_prefix, @$_) for @$call;
    }
  } else {
    $self->throw_exception (sprintf ("Don't know how to process conection actions of type '%s'", ref($call)) );
  }

  return $self;
}

sub connect_call_do_sql {
  my $self = shift;
  $self->_do_query(@_);
}

sub disconnect_call_do_sql {
  my $self = shift;
  $self->_do_query(@_);
}

# override in db-specific backend when necessary
sub connect_call_datetime_setup { 1 }

sub _do_query {
  my ($self, $action) = @_;

  if (ref $action eq 'CODE') {
    $action = $action->($self);
    $self->_do_query($_) foreach @$action;
  }
  else {
    # Most debuggers expect ($sql, @bind), so we need to exclude
    # the attribute hash which is the second argument to $dbh->do
    # furthermore the bind values are usually to be presented
    # as named arrayref pairs, so wrap those here too
    my @do_args = (ref $action eq 'ARRAY') ? (@$action) : ($action);
    my $sql = shift @do_args;
    my $attrs = shift @do_args;
    my @bind = map { [ undef, $_ ] } @do_args;

    $self->_query_start($sql, \@bind);
    $self->_get_dbh->do($sql, $attrs, @do_args);
    $self->_query_end($sql, \@bind);
  }

  return $self;
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

  try {
    if(ref $info[0] eq 'CODE') {
      $dbh = $info[0]->();
    }
    else {
      require DBI;
      $dbh = DBI->connect(@info);
    }

    if (!$dbh) {
      die $DBI::errstr;
    }

    unless ($self->unsafe) {

      $self->throw_exception(
        'Refusing clobbering of {HandleError} installed on externally supplied '
       ."DBI handle $dbh. Either remove the handler or use the 'unsafe' attribute."
      ) if $dbh->{HandleError} and ref $dbh->{HandleError} ne '__DBIC__DBH__ERROR__HANDLER__';

      # Default via _default_dbi_connect_attributes is 1, hence it was an explicit
      # request, or an external handle. Complain and set anyway
      unless ($dbh->{RaiseError}) {
        carp( ref $info[0] eq 'CODE'

          ? "The 'RaiseError' of the externally supplied DBI handle is set to false. "
           ."DBIx::Class will toggle it back to true, unless the 'unsafe' connect "
           .'attribute has been supplied'

          : 'RaiseError => 0 supplied in your connection_info, without an explicit '
           .'unsafe => 1. Toggling RaiseError back to true'
        );

        $dbh->{RaiseError} = 1;
      }

      # this odd anonymous coderef dereference is in fact really
      # necessary to avoid the unwanted effect described in perl5
      # RT#75792
      sub {
        my $weak_self = $_[0];
        weaken $weak_self;

        # the coderef is blessed so we can distinguish it from externally
        # supplied handles (which must be preserved)
        $_[1]->{HandleError} = bless sub {
          if ($weak_self) {
            $weak_self->throw_exception("DBI Exception: $_[0]");
          }
          else {
            # the handler may be invoked by something totally out of
            # the scope of DBIC
            DBIx::Class::Exception->throw("DBI Exception (unhandled by DBIC, ::Schema GCed): $_[0]");
          }
        }, '__DBIC__DBH__ERROR__HANDLER__';
      }->($self, $dbh);
    }
  }
  catch {
    $self->throw_exception("DBI Connection failed: $_")
  }
  finally {
    $DBI::connect_via = $old_connect_via if $old_connect_via;
  };

  $self->_dbh_autocommit($dbh->{AutoCommit});
  $dbh;
}

sub txn_begin {
  my $self = shift;

  # this means we have not yet connected and do not know the AC status
  # (e.g. coderef $dbh), need a full-fledged connection check
  if (! defined $self->_dbh_autocommit) {
    $self->ensure_connected;
  }
  # Otherwise simply connect or re-connect on pid changes
  else {
    $self->_get_dbh;
  }

  $self->next::method(@_);
}

sub _exec_txn_begin {
  my $self = shift;

  # if the user is utilizing txn_do - good for him, otherwise we need to
  # ensure that the $dbh is healthy on BEGIN.
  # We do this via ->dbh_do instead of ->dbh, so that the ->dbh "ping"
  # will be replaced by a failure of begin_work itself (which will be
  # then retried on reconnect)
  if ($self->{_in_do_block}) {
    $self->_dbh->begin_work;
  } else {
    $self->dbh_do(sub { $_[1]->begin_work });
  }
}

sub txn_commit {
  my $self = shift;

  $self->_verify_pid if $self->_dbh;
  $self->throw_exception("Unable to txn_commit() on a disconnected storage")
    unless $self->_dbh;

  # esoteric case for folks using external $dbh handles
  if (! $self->transaction_depth and ! $self->_dbh->FETCH('AutoCommit') ) {
    carp "Storage transaction_depth 0 does not match "
        ."false AutoCommit of $self->{_dbh}, attempting COMMIT anyway";
    $self->transaction_depth(1);
  }

  $self->next::method(@_);

  # if AutoCommit is disabled txn_depth never goes to 0
  # as a new txn is started immediately on commit
  $self->transaction_depth(1) if (
    !$self->transaction_depth
      and 
    defined $self->_dbh_autocommit
      and
    ! $self->_dbh_autocommit
  );
}

sub _exec_txn_commit {
  shift->_dbh->commit;
}

sub txn_rollback {
  my $self = shift;

  $self->_verify_pid if $self->_dbh;
  $self->throw_exception("Unable to txn_rollback() on a disconnected storage")
    unless $self->_dbh;

  # esoteric case for folks using external $dbh handles
  if (! $self->transaction_depth and ! $self->_dbh->FETCH('AutoCommit') ) {
    carp "Storage transaction_depth 0 does not match "
        ."false AutoCommit of $self->{_dbh}, attempting ROLLBACK anyway";
    $self->transaction_depth(1);
  }

  $self->next::method(@_);

  # if AutoCommit is disabled txn_depth never goes to 0
  # as a new txn is started immediately on commit
  $self->transaction_depth(1) if (
    !$self->transaction_depth
      and 
    defined $self->_dbh_autocommit
      and
    ! $self->_dbh_autocommit
  );
}

sub _exec_txn_rollback {
  shift->_dbh->rollback;
}

# generate some identical methods
for my $meth (qw/svp_begin svp_release svp_rollback/) {
  no strict qw/refs/;
  *{__PACKAGE__ ."::$meth"} = subname $meth => sub {
    my $self = shift;
    $self->_verify_pid if $self->_dbh;
    $self->throw_exception("Unable to $meth() on a disconnected storage")
      unless $self->_dbh;
    $self->next::method(@_);
  };
}

# This used to be the top-half of _execute.  It was split out to make it
#  easier to override in NoBindVars without duping the rest.  It takes up
#  all of _execute's args, and emits $sql, @bind.
sub _prep_for_execute {
  #my ($self, $op, $ident, $args) = @_;
  return shift->_gen_sql_bind(@_)
}

sub _gen_sql_bind {
  my ($self, $op, $ident, $args) = @_;

  my ($sql, @bind) = $self->sql_maker->$op(
    blessed($ident) ? $ident->from : $ident,
    @$args,
  );

  my (@final_bind, $colinfos);
  my $resolve_bindinfo = sub {
    $colinfos ||= $self->_resolve_column_info($ident);
    if (my $col = $_[1]->{dbic_colname}) {
      $_[1]->{sqlt_datatype} ||= $colinfos->{$col}{data_type}
        if $colinfos->{$col}{data_type};
      $_[1]->{sqlt_size} ||= $colinfos->{$col}{size}
        if $colinfos->{$col}{size};
    }
    $_[1];
  };

  for my $e (@{$args->[2]{bind}||[]}, @bind) {
    push @final_bind, [ do {
      if (ref $e ne 'ARRAY') {
        ({}, $e)
      }
      elsif (! defined $e->[0]) {
        ({}, $e->[1])
      }
      elsif (ref $e->[0] eq 'HASH') {
        (
          (first { $e->[0]{$_} } qw/dbd_attrs sqlt_datatype/) ? $e->[0] : $self->$resolve_bindinfo($e->[0]),
          $e->[1]
        )
      }
      elsif (ref $e->[0] eq 'SCALAR') {
        ( { sqlt_datatype => ${$e->[0]} }, $e->[1] )
      }
      else {
        ( $self->$resolve_bindinfo({ dbic_colname => $e->[0] }), $e->[1] )
      }
    }];
  }

  ($sql, \@final_bind);
}

sub _format_for_trace {
  #my ($self, $bind) = @_;

  ### Turn @bind from something like this:
  ###   ( [ "artist", 1 ], [ \%attrs, 3 ] )
  ### to this:
  ###   ( "'1'", "'3'" )

  map {
    defined( $_ && $_->[1] )
      ? qq{'$_->[1]'}
      : q{NULL}
  } @{$_[1] || []};
}

sub _query_start {
  my ( $self, $sql, $bind ) = @_;

  $self->debugobj->query_start( $sql, $self->_format_for_trace($bind) )
    if $self->debug;
}

sub _query_end {
  my ( $self, $sql, $bind ) = @_;

  $self->debugobj->query_end( $sql, $self->_format_for_trace($bind) )
    if $self->debug;
}

my $sba_compat;
sub _dbi_attrs_for_bind {
  my ($self, $ident, $bind) = @_;

  if (! defined $sba_compat) {
    $self->_determine_driver;
    $sba_compat = $self->can('source_bind_attributes') == \&source_bind_attributes
      ? 0
      : 1
    ;
  }

  my $sba_attrs;
  if ($sba_compat) {
    my $class = ref $self;
    carp_unique (
      "The source_bind_attributes() override in $class relies on a deprecated codepath. "
     .'You are strongly advised to switch your code to override bind_attribute_by_datatype() '
     .'instead. This legacy compat shim will also disappear some time before DBIC 0.09'
    );

    my $sba_attrs = $self->source_bind_attributes
  }

  my @attrs;

  for (map { $_->[0] } @$bind) {
    push @attrs, do {
      if (exists $_->{dbd_attrs}) {
        $_->{dbd_attrs}
      }
      elsif($_->{sqlt_datatype}) {
        # cache the result in the dbh_details hash, as it can not change unless
        # we connect to something else
        my $cache = $self->_dbh_details->{_datatype_map_cache} ||= {};
        if (not exists $cache->{$_->{sqlt_datatype}}) {
          $cache->{$_->{sqlt_datatype}} = $self->bind_attribute_by_data_type($_->{sqlt_datatype}) || undef;
        }
        $cache->{$_->{sqlt_datatype}};
      }
      elsif ($sba_attrs and $_->{dbic_colname}) {
        $sba_attrs->{$_->{dbic_colname}} || undef;
      }
      else {
        undef;  # always push something at this position
      }
    }
  }

  return \@attrs;
}

sub _execute {
  my ($self, $op, $ident, @args) = @_;

  my ($sql, $bind) = $self->_prep_for_execute($op, $ident, \@args);

  shift->dbh_do(    # retry over disconnects
    '_dbh_execute',
    $sql,
    $bind,
    $self->_dbi_attrs_for_bind($ident, $bind)
  );
}

sub _dbh_execute {
  my ($self, undef, $sql, $bind, $bind_attrs) = @_;

  $self->_query_start( $sql, $bind );
  my $sth = $self->_sth($sql);

  for my $i (0 .. $#$bind) {
    if (ref $bind->[$i][1] eq 'SCALAR') {  # any scalarrefs are assumed to be bind_inouts
      $sth->bind_param_inout(
        $i + 1, # bind params counts are 1-based
        $bind->[$i][1],
        $bind->[$i][0]{dbd_size} || $self->_max_column_bytesize($bind->[$i][0]), # size
        $bind_attrs->[$i],
      );
    }
    else {
      $sth->bind_param(
        $i + 1,
        (ref $bind->[$i][1] and overload::Method($bind->[$i][1], '""'))
          ? "$bind->[$i][1]"
          : $bind->[$i][1]
        ,
        $bind_attrs->[$i],
      );
    }
  }

  # Can this fail without throwing an exception anyways???
  my $rv = $sth->execute();
  $self->throw_exception(
    $sth->errstr || $sth->err || 'Unknown error: execute() returned false, but error flags were not set...'
  ) if !$rv;

  $self->_query_end( $sql, $bind );

  return (wantarray ? ($rv, $sth, @$bind) : $rv);
}

sub _prefetch_autovalues {
  my ($self, $source, $to_insert) = @_;

  my $colinfo = $source->columns_info;

  my %values;
  for my $col (keys %$colinfo) {
    if (
      $colinfo->{$col}{auto_nextval}
        and
      (
        ! exists $to_insert->{$col}
          or
        ref $to_insert->{$col} eq 'SCALAR'
          or
        (ref $to_insert->{$col} eq 'REF' and ref ${$to_insert->{$col}} eq 'ARRAY')
      )
    ) {
      $values{$col} = $self->_sequence_fetch(
        'NEXTVAL',
        ( $colinfo->{$col}{sequence} ||=
            $self->_dbh_get_autoinc_seq($self->_get_dbh, $source, $col)
        ),
      );
    }
  }

  \%values;
}

sub insert {
  my ($self, $source, $to_insert) = @_;

  my $prefetched_values = $self->_prefetch_autovalues($source, $to_insert);

  # fuse the values, but keep a separate list of prefetched_values so that
  # they can be fused once again with the final return
  $to_insert = { %$to_insert, %$prefetched_values };

  my $col_infos = $source->columns_info;
  my %pcols = map { $_ => 1 } $source->primary_columns;
  my %retrieve_cols;
  for my $col ($source->columns) {
    # nothing to retrieve when explicit values are supplied
    next if (defined $to_insert->{$col} and ! (
      ref $to_insert->{$col} eq 'SCALAR'
        or
      (ref $to_insert->{$col} eq 'REF' and ref ${$to_insert->{$col}} eq 'ARRAY')
    ));

    # the 'scalar keys' is a trick to preserve the ->columns declaration order
    $retrieve_cols{$col} = scalar keys %retrieve_cols if (
      $pcols{$col}
        or
      $col_infos->{$col}{retrieve_on_insert}
    );
  };

  my ($sqla_opts, @ir_container);
  if (%retrieve_cols and $self->_use_insert_returning) {
    $sqla_opts->{returning_container} = \@ir_container
      if $self->_use_insert_returning_bound;

    $sqla_opts->{returning} = [
      sort { $retrieve_cols{$a} <=> $retrieve_cols{$b} } keys %retrieve_cols
    ];
  }

  my ($rv, $sth) = $self->_execute('insert', $source, $to_insert, $sqla_opts);

  my %returned_cols = %$to_insert;
  if (my $retlist = $sqla_opts->{returning}) {  # if IR is supported - we will get everything in one set
    @ir_container = try {
      local $SIG{__WARN__} = sub {};
      my @r = $sth->fetchrow_array;
      $sth->finish;
      @r;
    } unless @ir_container;

    @returned_cols{@$retlist} = @ir_container if @ir_container;
  }
  else {
    # pull in PK if needed and then everything else
    if (my @missing_pri = grep { $pcols{$_} } keys %retrieve_cols) {

      $self->throw_exception( "Missing primary key but Storage doesn't support last_insert_id" )
        unless $self->can('last_insert_id');

      my @pri_values = $self->last_insert_id($source, @missing_pri);

      $self->throw_exception( "Can't get last insert id" )
        unless (@pri_values == @missing_pri);

      @returned_cols{@missing_pri} = @pri_values;
      delete $retrieve_cols{$_} for @missing_pri;
    }

    # if there is more left to pull
    if (%retrieve_cols) {
      $self->throw_exception(
        'Unable to retrieve additional columns without a Primary Key on ' . $source->source_name
      ) unless %pcols;

      my @left_to_fetch = sort { $retrieve_cols{$a} <=> $retrieve_cols{$b} } keys %retrieve_cols;

      my $cur = DBIx::Class::ResultSet->new($source, {
        where => { map { $_ => $returned_cols{$_} } (keys %pcols) },
        select => \@left_to_fetch,
      })->cursor;

      @returned_cols{@left_to_fetch} = $cur->next;

      $self->throw_exception('Duplicate row returned for PK-search after fresh insert')
        if scalar $cur->next;
    }
  }

  return { %$prefetched_values, %returned_cols };
}

sub insert_bulk {
  my ($self, $source, $cols, $data) = @_;

  # FIXME - perhaps this is not even needed? does DBI stringify?
  #
  # forcibly stringify whatever is stringifiable
  for my $r (0 .. $#$data) {
    for my $c (0 .. $#{$data->[$r]}) {
      $data->[$r][$c] = "$data->[$r][$c]"
        if ( ref $data->[$r][$c] and overload::Method($data->[$r][$c], '""') );
    }
  }

  # check the data for consistency
  # report a sensible error on bad data
  #
  # also create a list of dynamic binds (ones that will be changing
  # for each row)
  my $dyn_bind_idx;
  for my $col_idx (0..$#$cols) {

    # the first "row" is used as a point of reference
    my $reference_val = $data->[0][$col_idx];
    my $is_literal = ref $reference_val eq 'SCALAR';
    my $is_literal_bind = ( !$is_literal and (
      ref $reference_val eq 'REF'
        and
      ref $$reference_val eq 'ARRAY'
    ) );

    $dyn_bind_idx->{$col_idx} = 1
      if (!$is_literal and !$is_literal_bind);

    # use a closure for convenience (less to pass)
    my $bad_slice = sub {
      my ($msg, $slice_idx) = @_;
      $self->throw_exception(sprintf "%s for column '%s' in populate slice:\n%s",
        $msg,
        $cols->[$col_idx],
        do {
          require Data::Dumper::Concise;
          local $Data::Dumper::Maxdepth = 2;
          Data::Dumper::Concise::Dumper ({
            map { $cols->[$_] =>
              $data->[$slice_idx][$_]
            } (0 .. $#$cols)
          }),
        }
      );
    };

    for my $row_idx (1..$#$data) {  # we are comparing against what we got from [0] above, hence start from 1
      my $val = $data->[$row_idx][$col_idx];

      if ($is_literal) {
        if (ref $val ne 'SCALAR') {
          $bad_slice->(
            "Incorrect value (expecting SCALAR-ref \\'$$reference_val')",
            $row_idx
          );
        }
        elsif ($$val ne $$reference_val) {
          $bad_slice->(
            "Inconsistent literal SQL value (expecting \\'$$reference_val')",
            $row_idx
          );
        }
      }
      elsif ($is_literal_bind) {
        if (ref $val ne 'REF' or ref $$val ne 'ARRAY') {
          $bad_slice->(
            "Incorrect value (expecting ARRAYREF-ref \\['${$reference_val}->[0]', ... ])",
            $row_idx
          );
        }
        elsif (${$val}->[0] ne ${$reference_val}->[0]) {
          $bad_slice->(
            "Inconsistent literal SQL-bind value (expecting \\['${$reference_val}->[0]', ... ])",
            $row_idx
          );
        }
      }
      elsif (ref $val) {
        if (ref $val eq 'SCALAR' or (ref $val eq 'REF' and ref $$val eq 'ARRAY') ) {
          $bad_slice->("Literal SQL found where a plain bind value is expected", $row_idx);
        }
        else {
          $bad_slice->("$val reference found where bind expected", $row_idx);
        }
      }
    }
  }

  # Get the sql with bind values interpolated where necessary. For dynamic
  # binds convert the values of the first row into a literal+bind combo, with
  # extra positional info in the bind attr hashref. This will allow us to match
  # the order properly, and is so contrived because a user-supplied literal
  # bind (or something else specific to a resultsource and/or storage driver)
  # can inject extra binds along the way, so one can't rely on "shift
  # positions" ordering at all. Also we can't just hand SQLA a set of some
  # known "values" (e.g. hashrefs that can be later matched up by address),
  # because we want to supply a real value on which perhaps e.g. datatype
  # checks will be performed
  my ($sql, $proto_bind) = $self->_prep_for_execute (
    'insert',
    $source,
    [ { map { $cols->[$_] => $dyn_bind_idx->{$_}
      ? \[ '?', [
          { dbic_colname => $cols->[$_], _bind_data_slice_idx => $_ }
            =>
          $data->[0][$_]
        ] ]
      : $data->[0][$_]
    } (0..$#$cols) } ],
  );

  if (! @$proto_bind and keys %$dyn_bind_idx) {
    # if the bindlist is empty and we had some dynamic binds, this means the
    # storage ate them away (e.g. the NoBindVars component) and interpolated
    # them directly into the SQL. This obviosly can't be good for multi-inserts
    $self->throw_exception('Cannot insert_bulk without support for placeholders');
  }

  # neither _execute_array, nor _execute_inserts_with_no_binds are
  # atomic (even if _execute _array is a single call). Thus a safety
  # scope guard
  my $guard = $self->txn_scope_guard;

  $self->_query_start( $sql, @$proto_bind ? [[undef => '__BULK_INSERT__' ]] : () );
  my $sth = $self->_sth($sql);
  my $rv = do {
    if (@$proto_bind) {
      # proto bind contains the information on which pieces of $data to pull
      # $cols is passed in only for prettier error-reporting
      $self->_execute_array( $source, $sth, $proto_bind, $cols, $data );
    }
    else {
      # bind_param_array doesn't work if there are no binds
      $self->_dbh_execute_inserts_with_no_binds( $sth, scalar @$data );
    }
  };

  $self->_query_end( $sql, @$proto_bind ? [[ undef => '__BULK_INSERT__' ]] : () );

  $guard->commit;

  return (wantarray ? ($rv, $sth, @$proto_bind) : $rv);
}

sub _execute_array {
  my ($self, $source, $sth, $proto_bind, $cols, $data, @extra) = @_;

  ## This must be an arrayref, else nothing works!
  my $tuple_status = [];

  my $bind_attrs = $self->_dbi_attrs_for_bind($source, $proto_bind);

  # Bind the values by column slices
  for my $i (0 .. $#$proto_bind) {
    my $data_slice_idx = (
      ref $proto_bind->[$i][0] eq 'HASH'
        and
      exists $proto_bind->[$i][0]{_bind_data_slice_idx}
    ) ? $proto_bind->[$i][0]{_bind_data_slice_idx} : undef;

    $sth->bind_param_array(
      $i+1, # DBI bind indexes are 1-based
      defined $data_slice_idx
        # either get a "column" of dynamic values, or just repeat the same
        # bind over and over
        ? [ map { $_->[$data_slice_idx] } @$data ]
        : [ ($proto_bind->[$i][1]) x @$data ]
      ,
      defined $bind_attrs->[$i] ? $bind_attrs->[$i] : (), # some DBDs throw up when given an undef
    );
  }

  my ($rv, $err);
  try {
    $rv = $self->_dbh_execute_array($sth, $tuple_status, @extra);
  }
  catch {
    $err = shift;
  };

  # Not all DBDs are create equal. Some throw on error, some return
  # an undef $rv, and some set $sth->err - try whatever we can
  $err = ($sth->errstr || 'UNKNOWN ERROR ($sth->errstr is unset)') if (
    ! defined $err
      and
    ( !defined $rv or $sth->err )
  );

  # Statement must finish even if there was an exception.
  try {
    $sth->finish
  }
  catch {
    $err = shift unless defined $err
  };

  if (defined $err) {
    my $i = 0;
    ++$i while $i <= $#$tuple_status && !ref $tuple_status->[$i];

    $self->throw_exception("Unexpected populate error: $err")
      if ($i > $#$tuple_status);

    require Data::Dumper::Concise;
    $self->throw_exception(sprintf "execute_array() aborted with '%s' at populate slice:\n%s",
      ($tuple_status->[$i][1] || $err),
      Data::Dumper::Concise::Dumper( { map { $cols->[$_] => $data->[$i][$_] } (0 .. $#$cols) } ),
    );
  }

  return $rv;
}

sub _dbh_execute_array {
  #my ($self, $sth, $tuple_status, @extra) = @_;
  return $_[1]->execute_array({ArrayTupleStatus => $_[2]});
}

sub _dbh_execute_inserts_with_no_binds {
  my ($self, $sth, $count) = @_;

  my $err;
  try {
    my $dbh = $self->_get_dbh;
    local $dbh->{RaiseError} = 1;
    local $dbh->{PrintError} = 0;

    $sth->execute foreach 1..$count;
  }
  catch {
    $err = shift;
  };

  # Make sure statement is finished even if there was an exception.
  try {
    $sth->finish
  }
  catch {
    $err = shift unless defined $err;
  };

  $self->throw_exception($err) if defined $err;

  return $count;
}

sub update {
  #my ($self, $source, @args) = @_;
  shift->_execute('update', @_);
}


sub delete {
  #my ($self, $source, @args) = @_;
  shift->_execute('delete', @_);
}

# We were sent here because the $rs contains a complex search
# which will require a subquery to select the correct rows
# (i.e. joined or limited resultsets, or non-introspectable conditions)
#
# Generating a single PK column subquery is trivial and supported
# by all RDBMS. However if we have a multicolumn PK, things get ugly.
# Look at _multipk_update_delete()
sub _subq_update_delete {
  my $self = shift;
  my ($rs, $op, $values) = @_;

  my $rsrc = $rs->result_source;

  # quick check if we got a sane rs on our hands
  my @pcols = $rsrc->_pri_cols;

  my $sel = $rs->_resolved_attrs->{select};
  $sel = [ $sel ] unless ref $sel eq 'ARRAY';

  if (
      join ("\x00", map { join '.', $rs->{attrs}{alias}, $_ } sort @pcols)
        ne
      join ("\x00", sort @$sel )
  ) {
    $self->throw_exception (
      '_subq_update_delete can not be called on resultsets selecting columns other than the primary keys'
    );
  }

  if (@pcols == 1) {
    return $self->$op (
      $rsrc,
      $op eq 'update' ? $values : (),
      { $pcols[0] => { -in => $rs->as_query } },
    );
  }

  else {
    return $self->_multipk_update_delete (@_);
  }
}

# ANSI SQL does not provide a reliable way to perform a multicol-PK
# resultset update/delete involving subqueries. So by default resort
# to simple (and inefficient) delete_all style per-row opearations,
# while allowing specific storages to override this with a faster
# implementation.
#
sub _multipk_update_delete {
  return shift->_per_row_update_delete (@_);
}

# This is the default loop used to delete/update rows for multi PK
# resultsets, and used by mysql exclusively (because it can't do anything
# else).
#
# We do not use $row->$op style queries, because resultset update/delete
# is not expected to cascade (this is what delete_all/update_all is for).
#
# There should be no race conditions as the entire operation is rolled
# in a transaction.
#
sub _per_row_update_delete {
  my $self = shift;
  my ($rs, $op, $values) = @_;

  my $rsrc = $rs->result_source;
  my @pcols = $rsrc->_pri_cols;

  my $guard = $self->txn_scope_guard;

  # emulate the return value of $sth->execute for non-selects
  my $row_cnt = '0E0';

  my $subrs_cur = $rs->cursor;
  my @all_pk = $subrs_cur->all;
  for my $pks ( @all_pk) {

    my $cond;
    for my $i (0.. $#pcols) {
      $cond->{$pcols[$i]} = $pks->[$i];
    }

    $self->$op (
      $rsrc,
      $op eq 'update' ? $values : (),
      $cond,
    );

    $row_cnt++;
  }

  $guard->commit;

  return $row_cnt;
}

sub _select {
  my $self = shift;
  $self->_execute($self->_select_args(@_));
}

sub _select_args_to_query {
  my $self = shift;

  # my ($op, $ident, $select, $cond, $rs_attrs, $rows, $offset)
  #  = $self->_select_args($ident, $select, $cond, $attrs);
  my ($op, $ident, @args) =
    $self->_select_args(@_);

  # my ($sql, $prepared_bind) = $self->_gen_sql_bind($op, $ident, [ $select, $cond, $rs_attrs, $rows, $offset ]);
  my ($sql, $prepared_bind) = $self->_gen_sql_bind($op, $ident, \@args);
  $prepared_bind ||= [];

  return wantarray
    ? ($sql, $prepared_bind)
    : \[ "($sql)", @$prepared_bind ]
  ;
}

sub _select_args {
  my ($self, $ident, $select, $where, $attrs) = @_;

  my $sql_maker = $self->sql_maker;
  my ($alias2source, $rs_alias) = $self->_resolve_ident_sources ($ident);

  $attrs = {
    %$attrs,
    select => $select,
    from => $ident,
    where => $where,
    $rs_alias && $alias2source->{$rs_alias}
      ? ( _rsroot_rsrc => $alias2source->{$rs_alias} )
      : ()
    ,
  };

  # Sanity check the attributes (SQLMaker does it too, but
  # in case of a software_limit we'll never reach there)
  if (defined $attrs->{offset}) {
    $self->throw_exception('A supplied offset attribute must be a non-negative integer')
      if ( $attrs->{offset} =~ /\D/ or $attrs->{offset} < 0 );
  }

  if (defined $attrs->{rows}) {
    $self->throw_exception("The rows attribute must be a positive integer if present")
      if ( $attrs->{rows} =~ /\D/ or $attrs->{rows} <= 0 );
  }
  elsif ($attrs->{offset}) {
    # MySQL actually recommends this approach.  I cringe.
    $attrs->{rows} = $sql_maker->__max_int;
  }

  my @limit;

  # see if we need to tear the prefetch apart otherwise delegate the limiting to the
  # storage, unless software limit was requested
  if (
    #limited has_many
    ( $attrs->{rows} && keys %{$attrs->{collapse}} )
       ||
    # grouped prefetch (to satisfy group_by == select)
    ( $attrs->{group_by}
        &&
      @{$attrs->{group_by}}
        &&
      $attrs->{_prefetch_selector_range}
    )
  ) {
    ($ident, $select, $where, $attrs)
      = $self->_adjust_select_args_for_complex_prefetch ($ident, $select, $where, $attrs);
  }
  elsif (! $attrs->{software_limit} ) {
    push @limit, (
      $attrs->{rows} || (),
      $attrs->{offset} || (),
    );
  }

  # try to simplify the joinmap further (prune unreferenced type-single joins)
  $ident = $self->_prune_unused_joins ($ident, $select, $where, $attrs);

###
  # This would be the point to deflate anything found in $where
  # (and leave $attrs->{bind} intact). Problem is - inflators historically
  # expect a row object. And all we have is a resultsource (it is trivial
  # to extract deflator coderefs via $alias2source above).
  #
  # I don't see a way forward other than changing the way deflators are
  # invoked, and that's just bad...
###

  return ('select', $ident, $select, $where, $attrs, @limit);
}

# Returns a counting SELECT for a simple count
# query. Abstracted so that a storage could override
# this to { count => 'firstcol' } or whatever makes
# sense as a performance optimization
sub _count_select {
  #my ($self, $source, $rs_attrs) = @_;
  return { count => '*' };
}

sub source_bind_attributes {
  shift->throw_exception(
    'source_bind_attributes() was never meant to be a callable public method - '
   .'please contact the DBIC dev-team and describe your use case so that a reasonable '
   .'solution can be provided'
   ."\nhttp://search.cpan.org/dist/DBIx-Class/lib/DBIx/Class.pm#GETTING_HELP/SUPPORT"
  );
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
  return $self->cursor_class->new($self, \@_, $attrs);
}

sub select_single {
  my $self = shift;
  my ($rv, $sth, @bind) = $self->_select(@_);
  my @row = $sth->fetchrow_array;
  my @nextrow = $sth->fetchrow_array if @row;
  if(@row && @nextrow) {
    carp "Query returned more than one row.  SQL that returns multiple rows is DEPRECATED for ->find and ->single";
  }
  # Need to call finish() to work round broken DBDs
  $sth->finish();
  return @row;
}

=head2 sql_limit_dialect

This is an accessor for the default SQL limit dialect used by a particular
storage driver. Can be overridden by supplying an explicit L</limit_dialect>
to L<DBIx::Class::Schema/connect>. For a list of available limit dialects
see L<DBIx::Class::SQLMaker::LimitDialects>.

=head2 sth

=over 4

=item Arguments: $sql

=back

Returns a L<DBI> sth (statement handle) for the supplied SQL.

=cut

sub _dbh_sth {
  my ($self, $dbh, $sql) = @_;

  # 3 is the if_active parameter which avoids active sth re-use
  my $sth = $self->disable_sth_caching
    ? $dbh->prepare($sql)
    : $dbh->prepare_cached($sql, {}, 3);

  # XXX You would think RaiseError would make this impossible,
  #  but apparently that's not true :(
  $self->throw_exception(
    $dbh->errstr
      ||
    sprintf( "\$dbh->prepare() of '%s' through %s failed *silently* without "
            .'an exception and/or setting $dbh->errstr',
      length ($sql) > 20
        ? substr($sql, 0, 20) . '...'
        : $sql
      ,
      'DBD::' . $dbh->{Driver}{Name},
    )
  ) if !$sth;

  $sth;
}

sub sth {
  carp_unique 'sth was mistakenly marked/documented as public, stop calling it (will be removed before DBIC v0.09)';
  shift->_sth(@_);
}

sub _sth {
  my ($self, $sql) = @_;
  $self->dbh_do('_dbh_sth', $sql);  # retry over disconnects
}

sub _dbh_columns_info_for {
  my ($self, $dbh, $table) = @_;

  if ($dbh->can('column_info')) {
    my %result;
    my $caught;
    try {
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
    } catch {
      $caught = 1;
    };
    return \%result if !$caught && scalar keys %result;
  }

  my %result;
  my $sth = $dbh->prepare($self->sql_maker->select($table, undef, \'1 = 0'));
  $sth->execute;
  my @columns = @{$sth->{NAME_lc}};
  for my $i ( 0 .. $#columns ){
    my %column_info;
    $column_info{data_type} = $sth->{TYPE}->[$i];
    $column_info{size} = $sth->{PRECISION}->[$i];
    $column_info{is_nullable} = $sth->{NULLABLE}->[$i] ? 1 : 0;

    if ($column_info{data_type} =~ m/^(.*?)\((.*?)\)$/) {
      $column_info{data_type} = $1;
      $column_info{size}    = $2;
    }

    $result{$columns[$i]} = \%column_info;
  }
  $sth->finish;

  foreach my $col (keys %result) {
    my $colinfo = $result{$col};
    my $type_num = $colinfo->{data_type};
    my $type_name;
    if(defined $type_num && $dbh->can('type_info')) {
      my $type_info = $dbh->type_info($type_num);
      $type_name = $type_info->{TYPE_NAME} if $type_info;
      $colinfo->{data_type} = $type_name if $type_name;
    }
  }

  return \%result;
}

sub columns_info_for {
  my ($self, $table) = @_;
  $self->_dbh_columns_info_for ($self->_get_dbh, $table);
}

=head2 last_insert_id

Return the row id of the last insert.

=cut

sub _dbh_last_insert_id {
    my ($self, $dbh, $source, $col) = @_;

    my $id = try { $dbh->last_insert_id (undef, undef, $source->name, $col) };

    return $id if defined $id;

    my $class = ref $self;
    $self->throw_exception ("No storage specific _dbh_last_insert_id() method implemented in $class, and the generic DBI::last_insert_id() failed");
}

sub last_insert_id {
  my $self = shift;
  $self->_dbh_last_insert_id ($self->_dbh, @_);
}

=head2 _native_data_type

=over 4

=item Arguments: $type_name

=back

This API is B<EXPERIMENTAL>, will almost definitely change in the future, and
currently only used by L<::AutoCast|DBIx::Class::Storage::DBI::AutoCast> and
L<::Sybase::ASE|DBIx::Class::Storage::DBI::Sybase::ASE>.

The default implementation returns C<undef>, implement in your Storage driver if
you need this functionality.

Should map types from other databases to the native RDBMS type, for example
C<VARCHAR2> to C<VARCHAR>.

Types with modifiers should map to the underlying data type. For example,
C<INTEGER AUTO_INCREMENT> should become C<INTEGER>.

Composite types should map to the container type, for example
C<ENUM(foo,bar,baz)> becomes C<ENUM>.

=cut

sub _native_data_type {
  #my ($self, $data_type) = @_;
  return undef
}

# Check if placeholders are supported at all
sub _determine_supports_placeholders {
  my $self = shift;
  my $dbh  = $self->_get_dbh;

  # some drivers provide a $dbh attribute (e.g. Sybase and $dbh->{syb_dynamic_supported})
  # but it is inaccurate more often than not
  return try {
    local $dbh->{PrintError} = 0;
    local $dbh->{RaiseError} = 1;
    $dbh->do('select ?', {}, 1);
    1;
  }
  catch {
    0;
  };
}

# Check if placeholders bound to non-string types throw exceptions
#
sub _determine_supports_typeless_placeholders {
  my $self = shift;
  my $dbh  = $self->_get_dbh;

  return try {
    local $dbh->{PrintError} = 0;
    local $dbh->{RaiseError} = 1;
    # this specifically tests a bind that is NOT a string
    $dbh->do('select 1 where 1 = ?', {}, 1);
    1;
  }
  catch {
    0;
  };
}

=head2 sqlt_type

Returns the database driver name.

=cut

sub sqlt_type {
  shift->_get_dbh->{Driver}->{Name};
}

=head2 bind_attribute_by_data_type

Given a datatype from column info, returns a database specific bind
attribute for C<< $dbh->bind_param($val,$attribute) >> or nothing if we will
let the database planner just handle it.

Generally only needed for special case column types, like bytea in postgres.

=cut

sub bind_attribute_by_data_type {
    return;
}

=head2 is_datatype_numeric

Given a datatype from column_info, returns a boolean value indicating if
the current RDBMS considers it a numeric value. This controls how
L<DBIx::Class::Row/set_column> decides whether to mark the column as
dirty - when the datatype is deemed numeric a C<< != >> comparison will
be performed instead of the usual C<eq>.

=cut

sub is_datatype_numeric {
  #my ($self, $dt) = @_;

  return 0 unless $_[1];

  $_[1] =~ /^ (?:
    numeric | int(?:eger)? | (?:tiny|small|medium|big)int | dec(?:imal)? | real | float | double (?: \s+ precision)? | (?:big)?serial
  ) $/ix;
}


=head2 create_ddl_dir

=over 4

=item Arguments: $schema \@databases, $version, $directory, $preversion, \%sqlt_args

=back

Creates a SQL file based on the Schema, for each of the specified
database engines in C<\@databases> in the given directory.
(note: specify L<SQL::Translator> names, not L<DBI> driver names).

Given a previous version number, this will also create a file containing
the ALTER TABLE statements to transform the previous schema into the
current one. Note that these statements may contain C<DROP TABLE> or
C<DROP COLUMN> statements that can potentially destroy data.

The file names are created using the C<ddl_filename> method below, please
override this method in your schema if you would like a different file
name format. For the ALTER file, the same format is used, replacing
$version in the name with "$preversion-$version".

See L<SQL::Translator/METHODS> for a list of values for C<\%sqlt_args>.
The most common value for this would be C<< { add_drop_table => 1 } >>
to have the SQL produced include a C<DROP TABLE> statement for each table
created. For quoting purposes supply C<quote_table_names> and
C<quote_field_names>.

If no arguments are passed, then the following default values are assumed:

=over 4

=item databases  - ['MySQL', 'SQLite', 'PostgreSQL']

=item version    - $schema->schema_version

=item directory  - './'

=item preversion - <none>

=back

By default, C<\%sqlt_args> will have

 { add_drop_table => 1, ignore_constraint_names => 1, ignore_index_names => 1 }

merged with the hash passed in. To disable any of those features, pass in a
hashref like the following

 { ignore_constraint_names => 0, # ... other options }


WARNING: You are strongly advised to check all SQL files created, before applying
them.

=cut

sub create_ddl_dir {
  my ($self, $schema, $databases, $version, $dir, $preversion, $sqltargs) = @_;

  unless ($dir) {
    carp "No directory given, using ./\n";
    $dir = './';
  } else {
      -d $dir
        or
      (require File::Path and File::Path::make_path ("$dir"))  # make_path does not like objects (i.e. Path::Class::Dir)
        or
      $self->throw_exception(
        "Failed to create '$dir': " . ($! || $@ || 'error unknown')
      );
  }

  $self->throw_exception ("Directory '$dir' does not exist\n") unless(-d $dir);

  $databases ||= ['MySQL', 'SQLite', 'PostgreSQL'];
  $databases = [ $databases ] if(ref($databases) ne 'ARRAY');

  my $schema_version = $schema->schema_version || '1.x';
  $version ||= $schema_version;

  $sqltargs = {
    add_drop_table => 1,
    ignore_constraint_names => 1,
    ignore_index_names => 1,
    %{$sqltargs || {}}
  };

  unless (DBIx::Class::Optional::Dependencies->req_ok_for ('deploy')) {
    $self->throw_exception("Can't create a ddl file without " . DBIx::Class::Optional::Dependencies->req_missing_for ('deploy') );
  }

  my $sqlt = SQL::Translator->new( $sqltargs );

  $sqlt->parser('SQL::Translator::Parser::DBIx::Class');
  my $sqlt_schema = $sqlt->translate({ data => $schema })
    or $self->throw_exception ($sqlt->error);

  foreach my $db (@$databases) {
    $sqlt->reset();
    $sqlt->{schema} = $sqlt_schema;
    $sqlt->producer($db);

    my $file;
    my $filename = $schema->ddl_filename($db, $version, $dir);
    if (-e $filename && ($version eq $schema_version )) {
      # if we are dumping the current version, overwrite the DDL
      carp "Overwriting existing DDL file - $filename";
      unlink($filename);
    }

    my $output = $sqlt->translate;
    if(!$output) {
      carp("Failed to translate to $db, skipping. (" . $sqlt->error . ")");
      next;
    }
    if(!open($file, ">$filename")) {
      $self->throw_exception("Can't open $filename for writing ($!)");
      next;
    }
    print $file $output;
    close($file);

    next unless ($preversion);

    require SQL::Translator::Diff;

    my $prefilename = $schema->ddl_filename($db, $preversion, $dir);
    if(!-e $prefilename) {
      carp("No previous schema file found ($prefilename)");
      next;
    }

    my $difffile = $schema->ddl_filename($db, $version, $dir, $preversion);
    if(-e $difffile) {
      carp("Overwriting existing diff file - $difffile");
      unlink($difffile);
    }

    my $source_schema;
    {
      my $t = SQL::Translator->new($sqltargs);
      $t->debug( 0 );
      $t->trace( 0 );

      $t->parser( $db )
        or $self->throw_exception ($t->error);

      my $out = $t->translate( $prefilename )
        or $self->throw_exception ($t->error);

      $source_schema = $t->schema;

      $source_schema->name( $prefilename )
        unless ( $source_schema->name );
    }

    # The "new" style of producers have sane normalization and can support
    # diffing a SQL file against a DBIC->SQLT schema. Old style ones don't
    # And we have to diff parsed SQL against parsed SQL.
    my $dest_schema = $sqlt_schema;

    unless ( "SQL::Translator::Producer::$db"->can('preprocess_schema') ) {
      my $t = SQL::Translator->new($sqltargs);
      $t->debug( 0 );
      $t->trace( 0 );

      $t->parser( $db )
        or $self->throw_exception ($t->error);

      my $out = $t->translate( $filename )
        or $self->throw_exception ($t->error);

      $dest_schema = $t->schema;

      $dest_schema->name( $filename )
        unless $dest_schema->name;
    }

    my $diff = SQL::Translator::Diff::schema_diff($source_schema, $db,
                                                  $dest_schema,   $db,
                                                  $sqltargs
                                                 );
    if(!open $file, ">$difffile") {
      $self->throw_exception("Can't write to $difffile ($!)");
      next;
    }
    print $file $diff;
    close($file);
  }
}

=head2 deployment_statements

=over 4

=item Arguments: $schema, $type, $version, $directory, $sqlt_args

=back

Returns the statements used by L</deploy> and L<DBIx::Class::Schema/deploy>.

The L<SQL::Translator> (not L<DBI>) database driver name can be explicitly
provided in C<$type>, otherwise the result of L</sqlt_type> is used as default.

C<$directory> is used to return statements from files in a previously created
L</create_ddl_dir> directory and is optional. The filenames are constructed
from L<DBIx::Class::Schema/ddl_filename>, the schema name and the C<$version>.

If no C<$directory> is specified then the statements are constructed on the
fly using L<SQL::Translator> and C<$version> is ignored.

See L<SQL::Translator/METHODS> for a list of values for C<$sqlt_args>.

=cut

sub deployment_statements {
  my ($self, $schema, $type, $version, $dir, $sqltargs) = @_;
  $type ||= $self->sqlt_type;
  $version ||= $schema->schema_version || '1.x';
  $dir ||= './';
  my $filename = $schema->ddl_filename($type, $version, $dir);
  if(-f $filename)
  {
      # FIXME replace this block when a proper sane sql parser is available
      my $file;
      open($file, "<$filename")
        or $self->throw_exception("Can't open $filename ($!)");
      my @rows = <$file>;
      close($file);
      return join('', @rows);
  }

  unless (DBIx::Class::Optional::Dependencies->req_ok_for ('deploy') ) {
    $self->throw_exception("Can't deploy without a ddl_dir or " . DBIx::Class::Optional::Dependencies->req_missing_for ('deploy') );
  }

  # sources needs to be a parser arg, but for simplicty allow at top level
  # coming in
  $sqltargs->{parser_args}{sources} = delete $sqltargs->{sources}
      if exists $sqltargs->{sources};

  my $tr = SQL::Translator->new(
    producer => "SQL::Translator::Producer::${type}",
    %$sqltargs,
    parser => 'SQL::Translator::Parser::DBIx::Class',
    data => $schema,
  );

  my @ret;
  if (wantarray) {
    @ret = $tr->translate;
  }
  else {
    $ret[0] = $tr->translate;
  }

  $self->throw_exception( 'Unable to produce deployment statements: ' . $tr->error)
    unless (@ret && defined $ret[0]);

  return wantarray ? @ret : $ret[0];
}

# FIXME deploy() currently does not accurately report sql errors
# Will always return true while errors are warned
sub deploy {
  my ($self, $schema, $type, $sqltargs, $dir) = @_;
  my $deploy = sub {
    my $line = shift;
    return if(!$line);
    return if($line =~ /^--/);
    # next if($line =~ /^DROP/m);
    return if($line =~ /^BEGIN TRANSACTION/m);
    return if($line =~ /^COMMIT/m);
    return if $line =~ /^\s+$/; # skip whitespace only
    $self->_query_start($line);
    try {
      # do a dbh_do cycle here, as we need some error checking in
      # place (even though we will ignore errors)
      $self->dbh_do (sub { $_[1]->do($line) });
    } catch {
      carp qq{$_ (running "${line}")};
    };
    $self->_query_end($line);
  };
  my @statements = $schema->deployment_statements($type, undef, $dir, { %{ $sqltargs || {} }, no_comments => 1 } );
  if (@statements > 1) {
    foreach my $statement (@statements) {
      $deploy->( $statement );
    }
  }
  elsif (@statements == 1) {
    # split on single line comments and end of statements
    foreach my $line ( split(/\s*--.*\n|;\n/, $statements[0])) {
      $deploy->( $line );
    }
  }
}

=head2 datetime_parser

Returns the datetime parser class

=cut

sub datetime_parser {
  my $self = shift;
  return $self->{datetime_parser} ||= do {
    $self->build_datetime_parser(@_);
  };
}

=head2 datetime_parser_type

Defines the datetime parser class - currently defaults to L<DateTime::Format::MySQL>

=head2 build_datetime_parser

See L</datetime_parser>

=cut

sub build_datetime_parser {
  my $self = shift;
  my $type = $self->datetime_parser_type(@_);
  return $type;
}


=head2 is_replicating

A boolean that reports if a particular L<DBIx::Class::Storage::DBI> is set to
replicate from a master database.  Default is undef, which is the result
returned by databases that don't support replication.

=cut

sub is_replicating {
    return;

}

=head2 lag_behind_master

Returns a number that represents a certain amount of lag behind a master db
when a given storage is replicating.  The number is database dependent, but
starts at zero and increases with the amount of lag. Default in undef

=cut

sub lag_behind_master {
    return;
}

=head2 relname_to_table_alias

=over 4

=item Arguments: $relname, $join_count

=back

L<DBIx::Class> uses L<DBIx::Class::Relationship> names as table aliases in
queries.

This hook is to allow specific L<DBIx::Class::Storage> drivers to change the
way these aliases are named.

The default behavior is C<< "$relname_$join_count" if $join_count > 1 >>,
otherwise C<"$relname">.

=cut

sub relname_to_table_alias {
  my ($self, $relname, $join_count) = @_;

  my $alias = ($join_count && $join_count > 1 ?
    join('_', $relname, $join_count) : $relname);

  return $alias;
}

# The size in bytes to use for DBI's ->bind_param_inout, this is the generic
# version and it may be necessary to amend or override it for a specific storage
# if such binds are necessary.
sub _max_column_bytesize {
  my ($self, $attr) = @_;

  my $max_size;

  if ($attr->{sqlt_datatype}) {
    my $data_type = lc($attr->{sqlt_datatype});

    if ($attr->{sqlt_size}) {

      # String/sized-binary types
      if ($data_type =~ /^(?:
          l? (?:var)? char(?:acter)? (?:\s*varying)?
            |
          (?:var)? binary (?:\s*varying)? 
            |
          raw
        )\b/x
      ) {
        $max_size = $attr->{sqlt_size};
      }
      # Other charset/unicode types, assume scale of 4
      elsif ($data_type =~ /^(?:
          national \s* character (?:\s*varying)?
            |
          nchar
            |
          univarchar
            |
          nvarchar
        )\b/x
      ) {
        $max_size = $attr->{sqlt_size} * 4;
      }
    }

    if (!$max_size and !$self->_is_lob_type($data_type)) {
      $max_size = 100 # for all other (numeric?) datatypes
    }
  }

  $max_size || $self->_dbic_connect_attributes->{LongReadLen} || $self->_get_dbh->{LongReadLen} || 8000;
}

# Determine if a data_type is some type of BLOB
sub _is_lob_type {
  my ($self, $data_type) = @_;
  $data_type && ($data_type =~ /lob|bfile|text|image|bytea|memo/i
    || $data_type =~ /^long(?:\s+(?:raw|bit\s*varying|varbit|binary
                                  |varchar|character\s*varying|nvarchar
                                  |national\s*character\s*varying))?\z/xi);
}

sub _is_binary_lob_type {
  my ($self, $data_type) = @_;
  $data_type && ($data_type =~ /blob|bfile|image|bytea/i
    || $data_type =~ /^long(?:\s+(?:raw|bit\s*varying|varbit|binary))?\z/xi);
}

sub _is_text_lob_type {
  my ($self, $data_type) = @_;
  $data_type && ($data_type =~ /^(?:clob|memo)\z/i
    || $data_type =~ /^long(?:\s+(?:varchar|character\s*varying|nvarchar
                        |national\s*character\s*varying))\z/xi);
}

1;

=head1 USAGE NOTES

=head2 DBIx::Class and AutoCommit

DBIx::Class can do some wonderful magic with handling exceptions,
disconnections, and transactions when you use C<< AutoCommit => 1 >>
(the default) combined with L<txn_do|DBIx::Class::Storage/txn_do> for
transaction support.

If you set C<< AutoCommit => 0 >> in your connect info, then you are always
in an assumed transaction between commits, and you're telling us you'd
like to manage that manually.  A lot of the magic protections offered by
this module will go away.  We can't protect you from exceptions due to database
disconnects because we don't know anything about how to restart your
transactions.  You're on your own for handling all sorts of exceptional
cases if you choose the C<< AutoCommit => 0 >> path, just as you would
be with raw DBI.


=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

Andy Grundman <andy@hybridized.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
