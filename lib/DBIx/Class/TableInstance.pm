package DBIx::Class::TableInstance;

use strict;
use warnings;

use base qw/DBIx::Class/;
use DBIx::Class::Table;

__PACKAGE__->mk_classdata('table_alias'); # FIXME: Doesn't actually do anything yet!

__PACKAGE__->mk_classdata('table_class' => 'DBIx::Class::Table');

sub iterator_class { shift->result_source->resultset_class(@_) }
sub resultset_class { shift->result_source->resultset_class(@_) }
sub _table_name { shift->result_source->name }

=head1 NAME 

DBIx::Class::TableInstance - provides a classdata table object and method proxies

=head1 SYNOPSIS

  __PACKAGE__->table('foo');
  __PACKAGE__->add_columns(qw/id bar baz/);
  __PACKAGE__->set_primary_key('id');

=head1 METHODS

=cut

sub _mk_column_accessors {
  my ($class, @cols) = @_;
  $class->mk_group_accessors('column' => @cols);
}

=head2 add_columns

  __PACKAGE__->add_columns(qw/col1 col2 col3/);

Adds columns to the current class and creates accessors for them.

=cut

sub add_columns {
  my ($class, @cols) = @_;
  $class->result_source->add_columns(@cols);
  $class->_mk_column_accessors(@cols);
}

sub _select_columns {
  return shift->result_source->columns;
}

=head2 table

  __PACKAGE__->table('tbl_name');
  
Gets or sets the table name.

=cut

sub table {
  my ($class, $table) = @_;
  return $class->result_source->name unless $table;
  unless (ref $table) {
    $table = $class->table_class->new(
      {
        name => $table,
        result_class => $class,
      });
    if ($class->can('result_source')) {
      $table->{_columns} = { %{$class->result_source->{_columns}||{}} };
    }
  }
  $class->mk_classdata('result_source' => $table);
  if ($class->can('schema_instance')) {
    $class =~ m/([^:]+)$/;
    $class->schema_instance->register_class($class, $class);
  }
}

=head2 has_column                                                                
                                                                                
  if ($obj->has_column($col)) { ... }                                           
                                                                                
Returns 1 if the class has a column of this name, 0 otherwise.                  
                                                                                
=cut                                                                            

sub has_column {
  my ($self, $column) = @_;
  return $self->result_source->has_column($column);
}

=head2 column_info                                                               
                                                                                
  my $info = $obj->column_info($col);                                           
                                                                                
Returns the column metadata hashref for a column.
                                                                                
=cut                                                                            

sub column_info {
  my ($self, $column) = @_;
  return $self->result_source->column_info($column);
}

=head2 columns

  my @column_names = $obj->columns;                                             
                                                                                
=cut                                                                            

sub columns {
  return shift->result_source->columns(@_);
}

sub set_primary_key { shift->result_source->set_primary_key(@_); }
sub primary_columns { shift->result_source->primary_columns(@_); }

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

