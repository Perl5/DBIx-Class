# vim: ts=8:sw=4:sts=4:et
package DBIx::Class::Tree::AdjacencyList;
use strict;
use warnings;
use base qw( DBIx::Class );

=head1 NAME

DBIx::Class::Tree::AdjacencyList - Manage a tree of data using the common adjacency list model.

=head1 SYNOPSIS

Create a table for your tree data.

  CREATE TABLE employees (
    employee_id INTEGER PRIMARY KEY AUTOINCREMENT,
    parent_id INTEGER NOT NULL,
    name TEXT NOT NULL
  );

In your Schema or DB class add Tree::AdjacencyList to the top 
of the component list.

  __PACKAGE__->load_components(qw( Tree::AdjacencyList ... ));
  # If you want positionable data make sure this 
  # module comes first, as in:
  __PACKAGE__->load_components(qw( Tree::AdjacencyList Positional ... ));

Specify the column that contains the parent ID each row.

  package My::Employee;
  __PACKAGE__->parent_column('parent_id');

Thats it, now you can modify and analyze the tree.

  #!/use/bin/perl
  use My::Employee;
  
  my $employee = My::Employee->create({ name=>'Matt S. Trout' });
  
  my $rs = $employee->children();
  my @siblings = $employee->children();
  
  my $parent = $employee->parent();
  $employee->parent( 7 );

=head1 DESCRIPTION

This module provides methods for working with adjacency lists.  The 
adjacency list model is a very common way of representing a tree structure.  
In this model each row in a table has a prent ID column that references the 
primary key of another row in the same table.  Because of this the primary 
key must only be one column and is usually some sort of integer.  The row 
with a parent ID of 0 is the root row and is usually the parent of all 
other rows.

=head1 METHODS

=head2 parent_column

  __PACKAGE__->parent_column('parent_id');

Declares the name of the column that contains the self-referential 
ID which defines the parent row.  Defaults to "parent_id".

If you are useing the L<DBIx::Class::Positional> component then this 
parent_column will automatically be used as the collection_column.

=cut

__PACKAGE__->mk_classdata( 'parent_column' => 'parent_id' );

=head2 parent

  my $parent = $employee->parent();
  $employee->parent( $parent_obj );
  $employee->parent( $parent_id );

Retrieves the object's parent ID, or sets the object's 
parent ID.  If setting the parent ID then 0 will be returned 
if the object already has the specified parent, and 1 on 
success.

If you are using the L<DBIx::Class::Positional> component this 
module will first move the object to the last position of 
the list, change the parent ID, then move the object to the 
last position of the new list.  This ensures the intergrity 
of the positions.

=cut

sub parent {
    my( $self, $new_parent ) = @_;
    my $parent_column = $self->parent_column();
    if ($new_parent) {
        if (ref($new_parent)) {
            $new_parent = $new_parent->id() || 0;
        }
        return 0 if ($new_parent == ($self->get_column($parent_column)||0));
        my $is_positional = $self->isa('DBIx::Class::Positional');
        $self->move_last() if ($is_positional);
        $self->set_column( $parent_column => $new_parent );
        if ($is_positional) {
            $self->set_column(
                $self->position_column() => $self->search( {$self->_collection_clause()} )->count() + 1
            );
        }
        $self->update();
        return 1;
    }
    else {
        return $self->find( $self->get_column( $parent_column ) );
    }
}

=head2 children

  my $children_rs = $employee->children();
  my @children = $employee->children();

Returns a list or record set, depending on context, of all 
the objects one level below the current one.

If you are using the L<DBIx::Class::Positional> component then this method 
will return the children sorted by the position column.

=cut

sub children {
    my( $self ) = @_;
    my $rs = $self->search(
        { $self->parent_column()=>$self->id() },
        ( $self->isa('DBIx::Class::Position') ? {order_by=>$self->position_column()} : () )
    );
    return $rs->all() if (wantarray());
    return $rs;
}

=head1 PRIVATE METHODS

These methods are used internally.  You should never have the 
need to use them.

=head2 _collection_clause

This method is provided as an override of the method in 
L<DBIx::Class::Positional>.  This way Positional and Tree::AdjacencyList 
may be used together without conflict.  Make sure that in 
your component list that you load Tree::AdjacencyList before you 
load Positional.

=cut

sub _collection_clause {
    my( $self ) = @_;
    return (
        $self->parent_column() =>
        $self->get_column($self->parent_column())
    );
}

1;
__END__

=head1 AUTHOR

Aran Clary Deltac <bluefeet@cpan.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

