package DBIx::Class::Row;

use strict;
use warnings;

use base qw/DBIx::Class/;

=head1 NAME 

DBIx::Class::Row - Basic row methods

=head1 SYNOPSIS

=head1 DESCRIPTION

This class is responsible for defining and doing basic operations on rows
derived from L<DBIx::Class::Table> objects.

=head1 METHODS

=head2 new

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

=head2 insert

  $obj->insert;

Inserts an object into the database if it isn't already in there. Returns
the object itself.

=cut

sub insert {
  my ($self) = @_;
  return $self if $self->in_storage;
  #use Data::Dumper; warn Dumper($self);
  $self->storage->insert($self->_table_name, { $self->get_columns });
  $self->in_storage(1);
  $self->{_dirty_columns} = {};
  return $self;
}

=head2 in_storage

  $obj->in_storage; # Get value
  $obj->in_storage(1); # Set value

Indicated whether the object exists as a row in the database or not

=cut

sub in_storage {
  my ($self, $val) = @_;
  $self->{_in_storage} = $val if @_ > 1;
  return $self->{_in_storage};
}

=head2 update

  $obj->update;

Must be run on an object that is already in the database; issues an SQL
UPDATE query to commit any changes to the object to the db if required.

=cut

sub update {
  my ($self, $upd) = @_;
  $self->throw( "Not in database" ) unless $self->in_storage;
  my %to_update = $self->get_dirty_columns;
  return -1 unless keys %to_update;
  my $rows = $self->storage->update($self->result_source->from, \%to_update,
                                      $self->ident_condition);
  if ($rows == 0) {
    $self->throw( "Can't update ${self}: row not found" );
  } elsif ($rows > 1) {
    $self->throw("Can't update ${self}: updated more than one row");
  }
  $self->{_dirty_columns} = {};
  return $self;
}

=head2 delete

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
    $self->storage->delete($self->result_source->from, $self->ident_condition);
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

=head2 get_column

  my $val = $obj->get_column($col);

Gets a column value from a row object. Currently, does not do
any queries; the column must have already been fetched from
the database and stored in the object.

=cut

sub get_column {
  my ($self, $column) = @_;
  $self->throw( "Can't fetch data as class method" ) unless ref $self;
  return $self->{_column_data}{$column}
    if exists $self->{_column_data}{$column};
  $self->throw( "No such column '${column}'" ) unless $self->has_column($column);
  return undef;
}

=head2 get_columns

  my %data = $obj->get_columns;

Does C<get_column>, for all column values at once.

=cut

sub get_columns {
  my $self = shift;
  return return %{$self->{_column_data}};
}

=head2 get_dirty_columns

  my %data = $obj->get_dirty_columns;

Identical to get_columns but only returns those that have been changed.

=cut

sub get_dirty_columns {
  my $self = shift;
  return map { $_ => $self->{_column_data}{$_} }
           keys %{$self->{_dirty_columns}};
}

=head2 set_column

  $obj->set_column($col => $val);

Sets a column value. If the new value is different from the old one,
the column is marked as dirty for when you next call $obj->update.

=cut

sub set_column {
  my $self = shift;
  my ($column) = @_;
  my $old = $self->get_column($column);
  my $ret = $self->store_column(@_);
  $self->{_dirty_columns}{$column} = 1 unless defined $old && $old eq $ret;
  return $ret;
}

=head2 set_columns

  my $copy = $orig->set_columns({ $col => $val, ... });

Sets more than one column value at once.

=cut

sub set_columns {
  my ($self,$data) = @_;
  while (my ($col,$val) = each %$data) {
    $self->set_column($col,$val);
  }
}

=head2 copy

  my $copy = $orig->copy({ change => $to, ... });

Inserts a new row with the specified changes.

=cut

=head2 store_column

  $obj->store_column($col => $val);

Sets a column value without marking it as dirty.

=cut

sub store_column {
  my ($self, $column, $value) = @_;
  $self->throw( "No such column '${column}'" ) 
    unless exists $self->{_column_data}{$column} || $self->has_column($column);
  $self->throw( "set_column called for ${column} without value" ) 
    if @_ < 3;
  return $self->{_column_data}{$column} = $value;
}

=head2 inflate_result

  Class->inflate_result(\%me, \%prefetch?)

Called by ResultSet to inflate a result from storage

=cut

sub inflate_result {
  my ($class, $me, $prefetch) = @_;
  #use Data::Dumper; print Dumper(@_);
  my $new = bless({ _column_data => $me }, ref $class || $class);
  $new->in_storage(1);
  PRE: foreach my $pre (keys %{$prefetch||{}}) {
    my $rel_obj = $class->_relationships->{$pre};
    my $pre_class = $class->resolve_class($rel_obj->{class});
    my $fetched = $pre_class->inflate_result(@{$prefetch->{$pre}});
    $class->throw("No accessor for prefetched $pre")
      unless defined $rel_obj->{attrs}{accessor};
    if ($rel_obj->{attrs}{accessor} eq 'single') {
      PRIMARY: foreach my $pri ($rel_obj->{class}->primary_columns) {
        unless (defined $fetched->get_column($pri)) {
          undef $fetched;
          last PRIMARY;
        }
      }
      $new->{_relationship_data}{$pre} = $fetched;
    } elsif ($rel_obj->{attrs}{accessor} eq 'filter') {
      $new->{_inflated_column}{$pre} = $fetched;
    } else {
      $class->throw("Don't know how to store prefetched $pre");
    }
  }
  return $new;
}

sub copy {
  my ($self, $changes) = @_;
  my $new = bless({ _column_data => { %{$self->{_column_data}}} }, ref $self);
  $new->set_column($_ => $changes->{$_}) for keys %$changes;
  return $new->insert;
}

=head2 insert_or_update

  $obj->insert_or_update

Updates the object if it's already in the db, else inserts it.

=cut

sub insert_or_update {
  my $self = shift;
  return ($self->in_storage ? $self->update : $self->insert);
}

=head2 is_changed

  my @changed_col_names = $obj->is_changed

=cut

sub is_changed {
  return keys %{shift->{_dirty_columns} || {}};
}

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

