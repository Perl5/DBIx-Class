# vim: ts=8:sw=4:sts=4:et
package DBIx::Class::Positioned;
use strict;
use warnings;
use base qw( DBIx::Class );

=head1 NAME

DBIx::Class::Positioned - Modify the position of objects in an ordered list.

=head1 SYNOPSIS

Create a table for your positionable data.

  CREATE TABLE employees (
    employee_id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    position INTEGER NOT NULL
  );

In your Schema or DB class add Positioned to the top 
of the component list.

  __PACKAGE__->load_components(qw( Positioned ... ));

Specify the column that stores the position number for 
each row.

  package My::Employee;
  __PACKAGE__->position_column('position');

Thats it, now you can change the position of your objects.

  #!/use/bin/perl
  use My::Employee;
  
  my $employee = My::Employee->create({ name=>'Matt S. Trout' });
  
  my $rs = $employee->siblings();
  my @siblings = $employee->siblings();
  
  my $sibling;
  $sibling = $employee->first_sibling();
  $sibling = $employee->last_sibling();
  $sibling = $employee->previous_sibling();
  $sibling = $employee->next_sibling();
  
  $employee->move_previous();
  $employee->move_next();
  $employee->move_first();
  $employee->move_last();
  $employee->move_to( $position );

=head1 DESCRIPTION

This module provides a simple interface for modifying the position 
of DBIx::Class objects.

=head1 AUTO UPDATE

All of the move_* methods automatically update the rows involved in 
the query.  This is not configurable and is due to the fact that if you 
move a record it always causes other records in the list to be updated.

=head1 METHODS

=head2 position_column

  __PACKAGE__->position_column('position');

Sets and retrieves the name of the column that stores the 
positional value of each record.  Default to "position".

=cut

__PACKAGE__->mk_classdata( 'position_column' => 'position' );

=head2 collection_column

  __PACKAGE__->collection_column('thing_id');

This method specified a column to limit all queries in 
this module by.  This effectively allows you to have multiple 
positioned lists within the same table.

=cut

__PACKAGE__->mk_classdata( 'collection_column' );

=head2 siblings

  my $rs = $employee->siblings();
  my @siblings = $employee->siblings();

Returns either a result set or an array of all other objects 
excluding the one you called it on.

=cut

sub siblings {
    my( $self ) = @_;
    my $position_column = $self->position_column;
    my $rs = $self->result_source->resultset->search(
        {
            $position_column => { '!=' => $self->get_column($position_column) },
            $self->_collection_clause(),
        },
        { order_by => $self->position_column },
    );
    return $rs->all() if (wantarray());
    return $rs;
}

=head2 first_sibling

  my $sibling = $employee->first_sibling();

Returns the first sibling object.

=cut

sub first_sibling {
    my( $self ) = @_;
    return ($self->result_source->resultset->search(
        {
            $self->position_column => 1,
            $self->_collection_clause(),
        },
    )->all())[0];
}

=head2 last_sibling

  my $sibling = $employee->last_sibling();

Return the last sibling.

=cut

sub last_sibling {
    my( $self ) = @_;
    my $count = $self->result_source->resultset->search({$self->_collection_clause()})->count();
    return ($self->result_source->resultset->search(
        {
            $self->position_column => $count,
            $self->_collection_clause(),
        },
    )->all())[0];
}

=head2 previous_sibling

  my $sibling = $employee->previous_sibling();

Returns the sibling that resides one position higher.  Undef 
is returned if the current object is the first one.

=cut

sub previous_sibling {
    my( $self ) = @_;
    my $position_column = $self->position_column;
    my $position = $self->get_column( $position_column );
    return 0 if ($position==1);
    return ($self->result_source->resultset->search(
        {
            $position_column => $position - 1,
            $self->_collection_clause(),
        }
    )->all())[0];
}

=head2 next_sibling

  my $sibling = $employee->next_sibling();

Returns the sibling that resides one position lower.  Undef 
is returned if the current object is the last one.

=cut

sub next_sibling {
    my( $self ) = @_;
    my $position_column = $self->position_column;
    my $position = $self->get_column( $position_column );
    my $count = $self->result_source->resultset->search({$self->_collection_clause()})->count();
    return 0 if ($position==$count);
    return ($self->result_source->resultset->search(
        {
            $position_column => $position + 1,
            $self->_collection_clause(),
        },
    )->all())[0];
}

=head2 move_previous

  $employee->move_previous();

Swaps position with the sibling on position previous in the list.  
1 is returned on success, and 0 is returned if the objects is already 
the first one.

=cut

sub move_previous {
    my( $self ) = @_;
    my $position = $self->get_column( $self->position_column() );
    return $self->move_to( $position - 1 );
}

=head2 move_next

  $employee->move_next();

Swaps position with the sibling in the next position.  1 is returned on 
success, and 0 is returned if the object is already the last in the list.

=cut

sub move_next {
    my( $self ) = @_;
    my $position = $self->get_column( $self->position_column() );
    my $count = $self->result_source->resultset->search({$self->_collection_clause()})->count();
    return 0 if ($position==$count);
    return $self->move_to( $position + 1 );
}

=head2 move_first

  $employee->move_first();

Moves the object to the first position.  1 is returned on 
success, and 0 is returned if the object is already the first.

=cut

sub move_first {
    my( $self ) = @_;
    return $self->move_to( 1 );
}

=head2 move_last

  $employee->move_last();

Moves the object to the very last position.  1 is returned on 
success, and 0 is returned if the object is already the last one.

=cut

sub move_last {
    my( $self ) = @_;
    my $count = $self->result_source->resultset->search({$self->_collection_clause()})->count();
    return $self->move_to( $count );
}

=head2 move_to

  $employee->move_to( $position );

Moves the object to the specified position.  1 is returned on 
success, and 0 is returned if the object is already at the 
specified position.

=cut

sub move_to {
    my( $self, $to_position ) = @_;
    my $position_column = $self->position_column;
    my $from_position = $self->get_column( $position_column );
    return 0 if ( $to_position < 1 );
    return 0 if ( $from_position==$to_position );
    my $rs = $self->result_source->resultset->search({
        -and => [
            $position_column => { ($from_position>$to_position?'<':'>') => $from_position },
            $position_column => { ($from_position>$to_position?'>=':'<=') => $to_position },
        ],
        $self->_collection_clause(),
    });
    my $op = ($from_position>$to_position) ? '+' : '-';
    $rs->update({
        $position_column => \"$position_column $op 1",
    });
    $self->set_column( $position_column => $to_position );
    $self->update();
    return 1;
}

=head2 insert

Overrides the DBIC insert() method by providing a default 
position number.  The default will be the number of rows in 
the table +1, thus positioning the new record at the last position.

=cut

sub insert {
    my $self = shift;
    my $position_column = $self->position_column;
    $self->set_column( $position_column => $self->result_source->resultset->search( {$self->_collection_clause()} )->count()+1 ) 
        if (!$self->get_column($position_column));
    $self->next::method( @_ );
}

=head2 delete

Overrides the DBIC delete() method by first moving the object 
to the last position, then deleting it, thus ensuring the 
integrity of the positions.

=cut

sub delete {
    my $self = shift;
    $self->move_last;
    $self->next::method( @_ );
}

=head1 PRIVATE METHODS

These methods are used internally.  You should never have the 
need to use them.

=head2 _collection_clause

This method returns a name=>value pare for limiting a search 
by the collection column.  If the collection column is not 
defined then this will return an empty list.

=cut

sub _collection_clause {
    my $self = shift;
    if ($self->collection_column()) {
        return ( $self->collection_column() => $self->get_column($self->collection_column()) );
    }
    return ();
}

1;
__END__

=head1 BUGS

=head2 Race Condition on Insert

If a position is not specified for an insert than a position 
will be chosen based on COUNT(*)+1.  But, it first selects the 
count then inserts the record.  The space of time between select 
and insert introduces a race condition.  To fix this we need the 
ability to lock tables in DBIC.  I've added an entry in the TODO 
about this.

=head2 Multiple Moves

Be careful when issueing move_* methods to multiple objects.  If 
you've pre-loaded the objects then when you move one of the objects 
the position of the other object will not reflect their new value 
until you reload them from the database.

The are times when you will want to move objects as groups, such 
as changeing the parent of several objects at once - this directly 
conflicts with this problem.  One solution is for us to write a 
ResultSet class that supports a parent() method, for example.  Another 
solution is to somehow automagically modify the objects that exist 
in the current object's result set to have the new position value.

=head1 AUTHOR

Aran Deltac <bluefeet@cpan.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

