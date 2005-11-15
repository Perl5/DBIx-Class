package DBIx::Class::Row;

use strict;
use warnings;

=head1 NAME 

DBIx::Class::Row - Basic row methods

=head1 SYNOPSIS

=head1 DESCRIPTION

This class is responsible for defining and doing basic operations on rows
derived from L<DBIx::Class::Table> objects.

=head1 METHODS

=over 4

=item new

  my $obj = My::Class->new($attrs);

Creates a new row object from column => value mappings passed as a hash ref

=cut

sub new {
  my ($class, $attrs) = @_;
  $class = ref $class if ref $class;
  my $new = bless({ _column_data => { } }, $class);
  if ($attrs) {
    $new->throw("attrs must be a hashref" ) unless ref($attrs) eq 'HASH';
    while (my ($k, $v) = each %{$attrs}) {
      die "No such column $k on $class" unless $class->has_column($k);
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
  return $self if $self->in_storage;
  #use Data::Dumper; warn Dumper($self);
  my %in;
  $in{$_} = $self->get_column($_)
    for grep { defined $self->get_column($_) } $self->columns;
  my %out = %{ $self->storage->insert($self->_table_name, \%in) };
  $self->store_column($_, $out{$_})
    for grep { $self->get_column($_) ne $out{$_} } keys %out;
  $self->in_storage(1);
  $self->{_dirty_columns} = {};
  return $self;
}

=item in_storage

  $obj->in_storage; # Get value
  $obj->in_storage(1); # Set value

Indicated whether the object exists as a row in the database or not

=cut

sub in_storage {
  my ($self, $val) = @_;
  $self->{_in_storage} = $val if @_ > 1;
  return $self->{_in_storage};
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
  $self->throw( "Not in database" ) unless $self->in_storage;
  if (ref $upd eq 'HASH') {
    $self->$_($upd->{$_}) for keys %$upd;
  }
  my %to_update;
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

=item delete

  $obj->delete

Deletes the object from the database. The object is still perfectly usable
accessor-wise etc. but ->in_storage will now return 0 and the object must
be re ->insert'ed before it can be ->update'ed

=cut

sub delete {
  my $self = shift;
  if (ref $self) {
    $self->throw( "Not in database" ) unless $self->in_storage;
    #warn $self->_ident_cond.' '.join(', ', $self->_ident_values);
    $self->storage->delete($self->_table_name, $self->ident_condition);
    $self->in_storage(undef);
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
  $self->throw( "No such column '${column}'" ) unless $self->has_column($column);
  return $self->{_column_data}{$column}
    if exists $self->{_column_data}{$column};
  return undef;
}

=item get_columns

  my %data = $obj->get_columns;

Fetch all column values at once.

=cut

sub get_columns {
  my $self = shift;
  return map { $_ => $self->get_column($_) } $self->columns;
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

=item set_columns

  my $copy = $orig->set_columns({ $col => $val, ... });

Set more than one column value at once.

=cut

sub set_columns {
  my ($self,$data) = @_;
  while (my ($col,$val) = each %$data) {
    $self->set_column($col,$val);
  }
}

=item copy

  my $copy = $orig->copy({ change => $to, ... });

Insert a new row with the specified changes.

=cut

=item store_column

  $obj->store_column($col => $val);

Sets a column value without marking it as dirty

=cut

sub store_column {
  my ($self, $column, $value) = @_;
  $self->throw( "No such column '${column}'" ) 
    unless $self->has_column($column);
  $self->throw( "set_column called for ${column} without value" ) 
    if @_ < 3;
  return $self->{_column_data}{$column} = $value;
}

sub _row_to_object {
  my ($class, $cols, $row) = @_;
  my %vals;
  $vals{$cols->[$_]} = $row->[$_] for 0 .. $#$cols;
  my $new = bless({ _column_data => \%vals }, ref $class || $class);
  $new->in_storage(1);
  return $new;
}

sub copy {
  my ($self, $changes) = @_;
  my $new = bless({ _column_data => { %{$self->{_column_data}}} }, ref $self);
  $new->set_column($_ => $changes->{$_}) for keys %$changes;
  return $new->insert;
}

=item insert_or_update

  $obj->insert_or_update

Updates the object if it's already in the db, else inserts it

=cut

sub insert_or_update {
  my $self = shift;
  return ($self->in_storage ? $self->update : $self->insert);
}

=item is_changed

  my @changed_col_names = $obj->is_changed

=cut

sub is_changed {
  return keys %{shift->{_dirty_columns} || {}};
}

1;

=back

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

