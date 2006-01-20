package DBIx::Class::Row;

use strict;
use warnings;

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/AccessorGroup/);

__PACKAGE__->mk_group_accessors('simple' => 'result_source');

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
the object itself. Requires the object's result source to be set, or the
class to have a result_source_instance method.

=cut

sub insert {
  my ($self) = @_;
  return $self if $self->in_storage;
  $self->{result_source} ||= $self->result_source_instance
    if $self->can('result_source_instance');
  my $source = $self->{result_source};
  die "No result_source set on this object; can't insert" unless $source;
  #use Data::Dumper; warn Dumper($self);
  $source->storage->insert($source->from, { $self->get_columns });
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
  return $self unless keys %to_update;
  my $rows = $self->result_source->storage->update(
               $self->result_source->from, \%to_update, $self->ident_condition);
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
    $self->result_source->storage->delete(
      $self->result_source->from, $self->ident_condition);
    $self->in_storage(undef);
  } else {
    die "Can't do class delete without a ResultSource instance"
      unless $self->can('result_source_instance');
    my $attrs = { };
    if (@_ > 1 && ref $_[$#_] eq 'HASH') {
      $attrs = { %{ pop(@_) } };
    }
    my $query = (ref $_[0] eq 'HASH' ? $_[0] : {@_});
    $self->result_source_instance->resultset->search(@_)->delete;
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
  return %{$self->{_column_data}};
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
  $self->{_dirty_columns}{$column} = 1
    if (defined $old ^ defined $ret) || (defined $old && $old ne $ret);
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
  return $self;
}

=head2 copy

  my $copy = $orig->copy({ change => $to, ... });

Inserts a new row with the specified changes.

=cut

sub copy {
  my ($self, $changes) = @_;
  my $new = bless({ _column_data => { %{$self->{_column_data}}} }, ref $self);
  $new->set_column($_ => $changes->{$_}) for keys %$changes;
  return $new->insert;
}

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

  Class->inflate_result($result_source, \%me, \%prefetch?)

Called by ResultSet to inflate a result from storage

=cut

sub inflate_result {
  my ($class, $source, $me, $prefetch) = @_;
  #use Data::Dumper; print Dumper(@_);
  my $new = bless({ result_source => $source,
                    _column_data => $me,
                    _in_storage => 1
                  },
                  ref $class || $class);
  my $schema;
  PRE: foreach my $pre (keys %{$prefetch||{}}) {
    my $pre_source = $source->related_source($pre);
    die "Can't prefetch non-existant relationship ${pre}" unless $pre_source;
    my $fetched = $pre_source->result_class->inflate_result(
                    $pre_source, @{$prefetch->{$pre}});
    my $accessor = $source->relationship_info($pre)->{attrs}{accessor};
    $class->throw("No accessor for prefetched $pre")
      unless defined $accessor;
    PRIMARY: foreach my $pri ($pre_source->primary_columns) {
      unless (defined $fetched->get_column($pri)) {
        undef $fetched;
        last PRIMARY;
      }
    }
    if ($accessor eq 'single') {
      $new->{_relationship_data}{$pre} = $fetched;
    } elsif ($accessor eq 'filter') {
      $new->{_inflated_column}{$pre} = $fetched;
    } else {
      $class->throw("Don't know how to store prefetched $pre");
    }
  }
  return $new;
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

=head2 result_source

  Accessor to the ResultSource this object was created from

=cut

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

