package DBIx::Class::NestedSets;
use strict;
use warnings;

use base qw( DBIx::Class );

__PACKAGE__->mk_classdata( 'nested_left_column' );
__PACKAGE__->mk_classdata( 'nested_right_column' );

sub set_nested_columns {
    my( $class, $left_column, $right_column ) = @_;
    $class->nested_left_column( $left_column );
    $class->nested_right_column( $right_column );
}

sub append_child {
    my( $parent, $child ) = @_;

    # Preload these since we will be useing them more than once.
    my $right_column = $parent->nested_right_column();
    my $left_column = $parent->nested_left_column();
    my $parent_right = $parent->get($right_column);
    my $child_extent = $child->extent();

    # Find all nodes to the right of the parent, including the parent.
    my $rs = $parent->search( {
        $right_column => { '>=', $parent_right }
    } );

    # Shift all nodes to the right by the extent of the child.
    $rs->update(
        $right_column => {
            $right_column => { '+', $child_extent }
        }
    );

    # Pop the child in to the space that we opened up.
    $child->set(
        $left_column => $parent_right,
        $right_column => ($parent_right + $child_extent) - 1,
    );
}

sub extent {
    my( $self ) = @_;
    return (
        $self->get( $class->nested_right_column() ) -
        $self->get( $class->nested_left_column() )
    ) + 1;
}

1;
