package DBIx::Class::Table;

use strict;
use warnings;

use DBIx::Class::ResultSet;
use Data::Page;

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

This class is responsible for defining and doing table-level operations on 
L<DBIx::Class> classes.

=head1 METHODS

=cut

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

=head2 add_columns

  __PACKAGE__->add_columns(qw/col1 col2 col3/);

Adds columns to the current class and creates accessors for them.

=cut

sub add_columns {
  my ($class, @cols) = @_;
  $class->_register_columns(@cols);
  $class->_mk_column_accessors(@cols);
}

=head2 search_literal

  my @obj    = $class->search_literal($literal_where_cond, @bind);
  my $cursor = $class->search_literal($literal_where_cond, @bind);

=cut

sub search_literal {
  my ($class, $cond, @vals) = @_;
  $cond =~ s/^\s*WHERE//i;
  my $attrs = (ref $vals[$#vals] eq 'HASH' ? { %{ pop(@vals) } } : {});
  $attrs->{bind} = \@vals;
  return $class->search(\$cond, $attrs);
}

=head2 count_literal

  my $count = $class->count_literal($literal_where_cond);

=cut

sub count_literal {
  my $class = shift;
  return $class->search_literal(@_)->count;
}

=head2 count

  my $count = $class->count({ foo => 3 });

=cut

sub count {
  my $class = shift;
  return $class->search(@_)->count;
}

=head2 search 

  my @obj    = $class->search({ foo => 3 }); # "... WHERE foo = 3"
  my $cursor = $class->search({ foo => 3 });

To retrieve all rows, simply call C<search()> with no condition parameter,

  my @all = $class->search(); # equivalent to search({})

If you need to pass in additional attributes (see
L<DBIx::Class::ResultSet/Attributes> for details) an empty hash indicates
no condition,

  my @all = $class->search({}, { cols => [qw/foo bar/] }); # "SELECT foo, bar FROM $class_table"

=cut

sub search {
  my $class = shift;
  #warn "@_";
  my $attrs = { };
  if (@_ > 1 && ref $_[$#_] eq 'HASH') {
    $attrs = { %{ pop(@_) } };
  }
  $attrs->{where} = (@_ == 1 || ref $_[0] eq "HASH" ? shift: {@_});
  
  my $rs = $class->resultset($attrs);
  
  return (wantarray ? $rs->all : $rs);
}

sub resultset {
  my $class = shift;

  my $rs_class = $class->_resultset_class;
  eval "use $rs_class;";
  my $rs = $rs_class->new($class, @_);
}

=head2 search_like

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

=head2 table

  __PACKAGE__->table('tbl_name');
  
Gets or sets the table name.

=cut

sub table {
  shift->_table_name(@_);
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
  return exists $self->_columns->{$column};
}

=head2 column_info                                                               
                                                                                
  my $info = $obj->column_info($col);                                           
                                                                                
Returns the column metadata hashref for a column.
                                                                                
=cut                                                                            

sub column_info {
  my ($self, $column) = @_;
  die "No such column $column" unless exists $self->_columns->{$column};
  return $self->_columns->{$column};
}

=head2 columns                                                                   
                                                                                
  my @column_names = $obj->columns;                                             
                                                                                
=cut                                                                            

sub columns {
  die "columns() is a read-only accessor, did you mean add_columns()?" if (@_ > 1);
  return keys %{shift->_columns};
}

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

