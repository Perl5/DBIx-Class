package DBIx::Class::Table;

use strict;
use warnings;

use DBIx::Class::ResultSet;

use base qw/DBIx::Class/;

__PACKAGE__->mk_classdata('_columns' => {});

__PACKAGE__->mk_classdata('_table_name');

__PACKAGE__->mk_classdata('table_alias'); # FIXME: Doesn't actually do anything yet!

__PACKAGE__->mk_classdata('_resultset_class' => 'DBIx::Class::ResultSet');

sub iterator_class { shift->_resultset_class(@_) }

=head1 NAME 

DBIx::Class::Table - Basic table methods

=head1 SYNOPSIS

=head1 DESCRIPTION

This class is responsible for defining and doing basic operations on 
L<DBIx::Class> objects.

=head1 METHODS

=over 4

=cut

sub _register_columns {
  my ($class, @cols) = @_;
  my $names = { %{$class->_columns} };
  while (my $col = shift @cols) {
    $names->{$col} = (ref $cols[0] ? shift : {});
  }
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

sub resultset {
  my $class = shift;

  my $rs_class = $class->_resultset_class;
  eval "use $rs_class;";
  my $rs = $rs_class->new($class, @_);
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
  my $query    = ref $_[0] eq "HASH" ? { %{shift()} }: {@_};
  $query->{$_} = { 'like' => $query->{$_} } for keys %$query;
  return $class->search($query, { %$attrs });
}

sub _select_columns {
  return keys %{$_[0]->_columns};
}

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
  my $exists = $class->find($hash);
  return defined($exists) ? $exists : $class->create($hash);
}

=item has_column                                                                
                                                                                
  if ($obj->has_column($col)) { ... }                                           
                                                                                
Returns 1 if the object has a column of this name, 0 otherwise                  
                                                                                
=cut                                                                            

sub has_column {
  my ($self, $column) = @_;
  return exists $self->_columns->{$column};
}

=item column_info                                                               
                                                                                
  my $info = $obj->column_info($col);                                           
                                                                                
Returns the column metadata hashref for the column                              
                                                                                
=cut                                                                            

sub column_info {
  my ($self, $column) = @_;
  die "No such column $column" unless exists $self->_columns->{$column};
  return $self->_columns->{$column};
}

=item columns                                                                   
                                                                                
  my @column_names = $obj->columns;                                             
                                                                                
=cut                                                                            

sub columns { return keys %{shift->_columns}; }

1;

=back

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

