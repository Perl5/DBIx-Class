package DBIx::Class::Table;

use strict;
use warnings;

use DBIx::Class::ResultSet;

use Carp qw/croak/;

use base qw/DBIx::Class/;
__PACKAGE__->load_components(qw/AccessorGroup/);

__PACKAGE__->mk_group_accessors('simple' =>
  qw/_columns _primaries name resultset_class result_class schema/);

=head1 NAME 

DBIx::Class::Table - Table object

=head1 SYNOPSIS

=head1 DESCRIPTION

This class is responsible for defining and doing table-level operations on 
L<DBIx::Class> classes.

=head1 METHODS

=cut

sub new {
  my ($class, $attrs) = @_;
  $class = ref $class if ref $class;
  my $new = bless({ %{$attrs || {}} }, $class);
  $new->{resultset_class} ||= 'DBIx::Class::ResultSet';
  $new->{_columns} ||= {};
  $new->{name} ||= "!!NAME NOT SET!!";
  return $new;
}

sub add_columns {
  my ($self, @cols) = @_;
  while (my $col = shift @cols) {
    $self->_columns->{$col} = (ref $cols[0] ? shift : {});
  }
}

*add_column = \&add_columns;

=head2 add_columns

  $table->add_columns(qw/col1 col2 col3/);

  $table->add_columns('col1' => \%col1_info, 'col2' => \%col2_info, ...);

Adds columns to the table object. If supplied key => hashref pairs uses
the hashref as the column_info for that column.

=head2 add_column

  $table->add_column('col' => \%info?);

Convenience alias to add_columns

=cut

sub resultset {
  my $self = shift;
  return $self->{resultset} ||= $self->resultset_class->new($self);
}

=head2 has_column                                                                
                                                                                
  if ($obj->has_column($col)) { ... }                                           
                                                                                
Returns 1 if the table has a column of this name, 0 otherwise.                  
                                                                                
=cut                                                                            

sub has_column {
  my ($self, $column) = @_;
  return exists $self->_columns->{$column};
}

=head2 column_info                                                               
                                                                                
  my $info = $obj->column_info($col);                                           
                                                                                
Returns the column metadata hashref for a column.
                                                                                
=cut                                                                            

sub column_info {
  my ($self, $column) = @_;
  croak "No such column $column" unless exists $self->_columns->{$column};
  return $self->_columns->{$column};
}

=head2 columns

  my @column_names = $obj->columns;                                             
                                                                                
=cut                                                                            

sub columns {
  croak "columns() is a read-only accessor, did you mean add_columns()?" if (@_ > 1);
  return keys %{shift->_columns};
}

=head2 set_primary_key(@cols)                                                   
                                                                                
Defines one or more columns as primary key for this table. Should be            
called after C<add_columns>.
                                                                                
=cut                                                                            

sub set_primary_key {
  my ($self, @cols) = @_;
  # check if primary key columns are valid columns
  for (@cols) {
    $self->throw("No such column $_ on table ".$self->name)
      unless $self->has_column($_);
  }
  $self->_primaries(\@cols);
}

=head2 primary_columns                                                          
                                                                                
Read-only accessor which returns the list of primary keys.
                                                                                
=cut                                                                            

sub primary_columns {
  return @{shift->_primaries||[]};
}

=head2 from

Returns the FROM entry for the table (i.e. the table name)

=cut

sub from { shift->name; }

=head2 storage

Returns the storage handle for the current schema

=cut

sub storage { shift->schema->storage; }

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

