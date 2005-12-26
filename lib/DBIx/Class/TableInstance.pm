package DBIx::Class::TableInstance;

use strict;
use warnings;

use base qw/DBIx::Class/;
use DBIx::Class::Table;

__PACKAGE__->mk_classdata('table_alias'); # FIXME: Doesn't actually do anything yet!

__PACKAGE__->mk_classdata('_resultset_class' => 'DBIx::Class::ResultSet');
__PACKAGE__->mk_classdata('table_class' => 'DBIx::Class::Table');

sub iterator_class { shift->table_instance->resultset_class(@_) }
sub resultset_class { shift->table_instance->resultset_class(@_) }
sub _table_name { shift->table_instance->name }

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
  $class->table_instance->add_columns(@cols);
  $class->_mk_column_accessors(@cols);
}

sub _select_columns {
  return shift->table_instance->columns;
}

=head2 table

  __PACKAGE__->table('tbl_name');
  
Gets or sets the table name.

=cut

sub table {
  my ($class, $table) = @_;
  return $class->table_instance->name unless $table;
  unless (ref $table) {
    $table = $class->table_class->new(
      {
        name => $table,
        result_class => $class,
        #storage => $class->storage,
      });
    if ($class->can('table_instance')) {
      $table->{_columns} = { %{$class->table_instance->{_columns}||{}} };
    }
  }
  $class->mk_classdata('table_instance' => $table);
}

=head2 find_or_create

  $class->find_or_create({ key => $val, ... });

Searches for a record matching the search condition; if it doesn't find one,
creates one and returns that instead.

=cut

sub find_or_create {
  my $class    = shift;
  my $hash     = ref $_[0] eq "HASH" ? shift: {@_};
  my $exists = $class->find($hash);
  return defined($exists) ? $exists : $class->create($hash);
}

=head2 has_column                                                                
                                                                                
  if ($obj->has_column($col)) { ... }                                           
                                                                                
Returns 1 if the class has a column of this name, 0 otherwise.                  
                                                                                
=cut                                                                            

sub has_column {
  my ($self, $column) = @_;
  return $self->table_instance->has_column($column);
}

=head2 column_info                                                               
                                                                                
  my $info = $obj->column_info($col);                                           
                                                                                
Returns the column metadata hashref for a column.
                                                                                
=cut                                                                            

sub column_info {
  my ($self, $column) = @_;
  return $self->table_instance->column_info($column);
}

=head2 columns                                                                   
                                                                                
  my @column_names = $obj->columns;                                             
                                                                                
=cut                                                                            

sub columns {
  return shift->table_instance->columns(@_);
}

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

