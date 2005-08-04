package DBIx::Class::Table;

use strict;
use warnings;

use DBIx::Class::Cursor;

use base qw/Class::Data::Inheritable/;

__PACKAGE__->mk_classdata('_columns' => {});

__PACKAGE__->mk_classdata('_table_name');

__PACKAGE__->mk_classdata('table_alias'); # FIXME: Doesn't actually do anything yet!

__PACKAGE__->mk_classdata('_cursor_class' => 'DBIx::Class::Cursor');

sub iterator_class { shift->_cursor_class(@_) }

=head1 NAME 

DBIx::Class::Table - Basic table methods

=head1 SYNOPSIS

=head1 DESCRIPTION

This class is responsible for defining and doing basic operations on 
L<DBIx::Class> objects.

=head1 METHODS

=over 4

=item new

  my $obj = My::Class->new($attrs);

Creates a new object from column => value mappings passed as a hash ref

=cut

sub new {
  my ($class, $attrs) = @_;
  $class = ref $class if ref $class;
  my $new = bless({ _column_data => { } }, $class);
  if ($attrs) {
    $new->throw("attrs must be a hashref" ) unless ref($attrs) eq 'HASH';
    while (my ($k, $v) = each %{$attrs}) {
      $new->store_column($k => $v);
    }
  }
  return $new;
}

=item insert

  $obj->insert;

Inserts an object into the database if it isn't already in there. Returns
the object itself.

=cut

sub insert {
  my ($self) = @_;
  return $self if $self->in_database;
  #use Data::Dumper; warn Dumper($self);
  my %in;
  $in{$_} = $self->get_column($_)
    for grep { defined $self->get_column($_) } $self->columns;
  my %out = %{ $self->storage->insert($self->_table_name, \%in) };
  $self->store_column($_, $out{$_})
    for grep { $self->get_column($_) ne $out{$_} } keys %out;
  $self->in_database(1);
  $self->{_dirty_columns} = {};
  return $self;
}

=item in_database

  $obj->in_database; # Get value
  $obj->in_database(1); # Set value

Indicated whether the object exists as a row in the database or not

=cut

sub in_database {
  my ($self, $val) = @_;
  $self->{_in_database} = $val if @_ > 1;
  return $self->{_in_database};
}

=item create

  my $new = My::Class->create($attrs);

A shortcut for My::Class->new($attrs)->insert;

=cut

sub create {
  my ($class, $attrs) = @_;
  $class->throw( "create needs a hashref" ) unless ref $attrs eq 'HASH';
  return $class->new($attrs)->insert;
}

=item update

  $obj->update;

Must be run on an object that is already in the database; issues an SQL
UPDATE query to commit any changes to the object to the db if required.

=cut

sub update {
  my ($self, $upd) = @_;
  $self->throw( "Not in database" ) unless $self->in_database;
  my %to_update = %{$upd || {}};
  $to_update{$_} = $self->get_column($_) for $self->is_changed;
  return -1 unless keys %to_update;
  my $rows = $self->storage->update($self->_table_name, \%to_update,
                                      $self->ident_condition);
  if ($rows == 0) {
    $self->throw( "Can't update ${self}: row not found" );
  } elsif ($rows > 1) {
    $self->throw("Can't update ${self}: updated more than one row");
  }
  $self->{_dirty_columns} = {};
  return $self;
}

sub ident_condition {
  my ($self) = @_;
  my %cond;
  $cond{$_} = $self->get_column($_) for keys %{$self->_primaries};
  return \%cond;
}

=item delete

  $obj->delete

Deletes the object from the database. The object is still perfectly usable
accessor-wise etc. but ->in_database will now return 0 and the object must
be re ->insert'ed before it can be ->update'ed

=cut

sub delete {
  my $self = shift;
  if (ref $self) {
    $self->throw( "Not in database" ) unless $self->in_database;
    #warn $self->_ident_cond.' '.join(', ', $self->_ident_values);
    $self->storage->delete($self->_table_name, $self->ident_condition);
    $self->in_database(undef);
    #$self->store_column($_ => undef) for $self->primary_columns;
      # Should probably also arrange to trash PK if auto
      # but if we do, post-delete cascade triggers fail :/
  } else {
    my $attrs = { };
    if (@_ > 1 && ref $_[$#_] eq 'HASH') {
      $attrs = { %{ pop(@_) } };
    }
    my $query = (ref $_[0] eq 'HASH' ? $_[0] : {@_});
    $self->storage->delete($self->_table_name, $query);
  }
  return $self;
}

=item get_column

  my $val = $obj->get_column($col);

Fetches a column value

=cut

sub get_column {
  my ($self, $column) = @_;
  $self->throw( "Can't fetch data as class method" ) unless ref $self;
  $self->throw( "No such column '${column}'" ) unless $self->_columns->{$column};
  return $self->{_column_data}{$column}
    if exists $self->{_column_data}{$column};
  return undef;
}

=item set_column

  $obj->set_column($col => $val);

Sets a column value; if the new value is different to the old the column
is marked as dirty for when you next call $obj->update

=cut

sub set_column {
  my $self = shift;
  my ($column) = @_;
  my $old = $self->get_column($column);
  my $ret = $self->store_column(@_);
  $self->{_dirty_columns}{$column} = 1 unless defined $old && $old eq $ret;
  return $ret;
}

=item store_column

  $obj->store_column($col => $val);

Sets a column value without marking it as dirty

=cut

sub store_column {
  my ($self, $column, $value) = @_;
  $self->throw( "No such column '${column}'" ) 
    unless $self->_columns->{$column};
  $self->throw( "set_column called for ${column} without value" ) 
    if @_ < 3;
  return $self->{_column_data}{$column} = $value;
}

sub _register_columns {
  my ($class, @cols) = @_;
  my $names = { %{$class->_columns} };
  $names->{$_} ||= {} for @cols;
  $class->_columns($names); 
}

sub _mk_column_accessors {
  my ($class, @cols) = @_;
  $class->mk_group_accessors('column' => @cols);
}

=item add_columns

  __PACKAGE__->add_columns(qw/col1 col2 col3/);

Adds columns to the current package, and creates accessors for them

=cut

sub add_columns {
  my ($class, @cols) = @_;
  $class->_register_columns(@cols);
  $class->_mk_column_accessors(@cols);
}

=item retrieve_from_sql

  my @obj    = $class->retrieve_from_sql($sql_where_cond, @bind);
  my $cursor = $class->retrieve_from_sql($sql_where_cond, @bind);

=cut

sub retrieve_from_sql {
  my ($class, $cond, @vals) = @_;
  $cond =~ s/^\s*WHERE//i;
  my $attrs = (ref $vals[$#vals] eq 'HASH' ? pop(@vals) : {});
  my @cols = $class->_select_columns($attrs);
  #warn "@cols $cond @vals";
  return $class->sth_to_objects(undef, \@vals, \@cols, { where => \$cond });
}

=item count_from_sql

  my $count = $class->count($sql_where_cond);

=cut

sub count_from_sql {
  my ($self, $cond, @vals) = @_;
  $cond =~ s/^\s*WHERE//i;
  my $attrs = (ref $vals[$#vals] eq 'HASH' ? pop(@vals) : {});
  my @cols = 'COUNT(*)';
  $attrs->{bind} = [ @vals ];
  my $sth = $self->storage->select($self->_table_name,\@cols,\$cond, $attrs);
  #warn "$cond @vals";
  my ($count) = $sth->fetchrow_array;
  $sth->finish;
  return $count;
}

=item count

  my $count = $class->count({ foo => 3 });

=cut

sub count {
  my $class = shift;
  my $attrs = { };
  if (@_ > 1 && ref $_[$#_] eq 'HASH') {
    $attrs = { %{ pop(@_) } };
  }
  my $query    = ref $_[0] eq "HASH" || (@_ == 1) ? shift: {@_};
  my ($cond)  = $class->_cond_resolve($query, $attrs);
  return $class->count_from_sql($cond, @{$attrs->{bind}||[]}, $attrs);
}

=item sth_to_objects

  my @obj    = $class->sth_to_objects($sth, \@bind, \@columns, $attrs);
  my $cursor = $class->sth_to_objects($sth, \@bind, \@columns, $attrs);

=cut

sub sth_to_objects {
  my ($class, $sth, $args, $cols, $attrs) = @_;
  my @cols = ((ref $cols eq 'ARRAY') ? @$cols : @{$sth->{NAME_lc}} );
  my @args = map { ref $_ ? ''.$_ : $_ } @$args; # Stringify objects
  my $cursor_class = $class->_cursor_class;
  eval "use $cursor_class;";
  my $cursor = $cursor_class->new($class, $sth, \@args, \@cols, $attrs);
  return (wantarray ? $cursor->all : $cursor);
}

sub _row_to_object { # WARNING: Destructive to @$row
  my ($class, $cols, $row) = @_;
  my $new = $class->new;
  $new->store_column($_, shift @$row) for @$cols;
  $new->in_database(1);
  return $new;
}

=item search 

  my @obj    = $class->search({ foo => 3 });
  my $cursor = $class->search({ foo => 3 });

=cut

sub search {
  my $class = shift;
  #warn "@_";
  my $attrs = { };
  if (@_ > 1 && ref $_[$#_] eq 'HASH') {
    $attrs = { %{ pop(@_) } };
  }
  my $query    = ref $_[0] eq "HASH" ? shift: {@_};
  my ($cond, @param)  = $class->_cond_resolve($query, $attrs);
  return $class->retrieve_from_sql($cond, @param, $attrs);
}

=item search_like

Identical to search except defaults to 'LIKE' instead of '=' in condition

=cut

sub search_like {
  my $class    = shift;
  my $attrs = { };
  if (@_ > 1 && ref $_[$#_] eq 'HASH') {
    $attrs = pop(@_);
  }
  return $class->search(@_, { %$attrs, cmp => 'LIKE' });
}

sub _select_columns {
  return keys %{$_[0]->_columns};
}

=item copy

  my $copy = $orig->copy({ change => $to, ... });

=cut

sub copy {
  my ($self, $changes) = @_;
  my $new = bless({ _column_data => { %{$self->{_column_data}}} }, ref $self);
  $new->set_column($_ => $changes->{$_}) for keys %$changes;
  return $new->insert;
}

#sub _cond_resolve {
#  my ($self, $query, $attrs) = @_;
#  return '1 = 1' unless keys %$query;
#  my $op = $attrs->{'cmp'} || '=';
#  my $cond = join(' AND ',
#               map { (defined $query->{$_}
#                       ? "$_ $op ?"
#                       : (do { delete $query->{$_}; "$_ IS NULL"; }));
#                   } keys %$query);
#  return ($cond, values %$query);
#}

=item table

  __PACKAGE__->table('tbl_name');

=cut

sub table {
  shift->_table_name(@_);
}

=item find_or_create

  $class->find_or_create({ key => $val, ... });

Searches for a record matching the search condition; if it doesn't find one,
creates one and returns that instead

=cut

sub find_or_create {
  my $class    = shift;
  my $hash     = ref $_[0] eq "HASH" ? shift: {@_};
  my ($exists) = $class->search($hash);
  return defined($exists) ? $exists : $class->create($hash);
}

=item insert_or_update

  $obj->insert_or_update

Updates the object if it's already in the db, else inserts it

=cut

sub insert_or_update {
  my $self = shift;
  return ($self->in_database ? $self->update : $self->insert);
}

=item retrieve_all

  my @all = $class->retrieve_all;

=cut

sub retrieve_all {
  my ($class) = @_;
  return $class->retrieve_from_sql( '1' );
}

=item is_changed

  my @changed_col_names = $obj->is_changed

=cut

sub is_changed {
  return keys %{shift->{_dirty_columns} || {}};
}

sub columns { return keys %{shift->_columns}; }

1;

=back

=head1 AUTHORS

Matt S. Trout <perl-stuff@trout.me.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

