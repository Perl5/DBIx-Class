package DBIx::Class::Table;

use strict;
use warnings;

use DBIx::Class::ResultSet;

use Carp qw/croak/;

use base qw/DBIx::Class/;
__PACKAGE__->load_components(qw/AccessorGroup/);

__PACKAGE__->mk_group_accessors('simple' =>
  qw/_columns name resultset_class result_class storage/);

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
  my $new = bless($attrs || {}, $class);
  $new->{resultset_class} ||= 'DBIx::Class::ResultSet';
  $new->{_columns} ||= {};
  $new->{name} ||= "!!NAME NOT SET!!";
  return $new;
}

sub add_columns {
  my ($self, @cols) = @_;
  while (my $col = shift @cols) {
    $self->add_column($col => (ref $cols[0] ? shift : {}));
  }
}

sub add_column {
  my ($self, $col, $info) = @_;
  $self->_columns->{$col} = $info || {};
}

=head2 add_columns

  $table->add_columns(qw/col1 col2 col3/);

  $table->add_columns('col1' => \%col1_info, 'col2' => \%col2_info, ...);

Adds columns to the table object. If supplied key => hashref pairs uses
the hashref as the column_info for that column.

=cut

sub resultset {
  my $self = shift;
  my $rs_class = $self->resultset_class;
  eval "use $rs_class;";
  return $rs_class->new($self);
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

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

