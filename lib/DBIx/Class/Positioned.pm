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

=head1 METHODS

=head2 position_column

  __PACKAGE__->position_column('position');

Sets and retrieves the name of the column that stores the 
positional value of each record.  Default to "position".

=cut

__PACKAGE__->mk_classdata( 'position_column' => 'position' );

=head2 siblings

  my $rs = $employee->siblings();
  my @siblings = $employee->siblings();

Returns either a result set or an array of all other objects 
excluding the one you called it on.

=cut

sub siblings {
    my( $self ) = @_;
    my $position_column = $self->position_column;
    my $rs = $self->search(
        { $position_column => { '!=' => $self->get_column($position_column) } },
        { order_by => $self->position_column },
    );
    if (wantarray()) { return $rs->all(); }
    else { return $rs; }
}

=head2 first_sibling

  my $sibling = $employee->first_sibling();

Returns the first sibling object.

=cut

sub first_sibling {
    my( $self ) = @_;
    return ($self->search(
        {},
        { rows=>1, order_by => $self->position_column },
    )->all())[0];
}

=head2 last_sibling

  my $sibling = $employee->last_sibling();

Return the last sibling.

=cut

sub last_sibling {
    my( $self ) = @_;
    return ($self->search(
        {},
        { rows=>1, order_by => $self->position_column.' DESC' },
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
    return ($self->search(
        { $position_column => { '<' => $self->get_column($position_column) } },
        { rows=>1, order_by => $position_column.' DESC' },
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
    return ($self->search(
        { $position_column => { '>' => $self->get_column($position_column) } },
        { rows=>1, order_by => $position_column },
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
    my $previous = $self->previous_sibling();
    return undef if (!$previous);
    my $position_column = $self->position_column;
    my $self_position = $self->get_column( $position_column );
    $self->set_column( $position_column, $previous->get_column($position_column) );
    $previous->set_column( $position_column, $self_position );
    $self->update();
    $previous->update();
    return 1;
}

=head2 move_next

  $employee->move_next();

Swaps position with the sibling in the next position.  1 is returned on 
success, and 0 is returned if the object is already the last in the list.

=cut

sub move_next {
    my( $self ) = @_;
    my $next = $self->next_sibling();
    return undef if (!$next);
    my $position_column = $self->position_column;
    my $self_position = $self->get_column( $position_column );
    $self->set_column( $position_column, $next->get_column($position_column) );
    $next->set_column( $position_column, $self_position );
    $self->update();
    $next->update();
    return 1;
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
    my $count = $self->search()->count();
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
    return undef if ( $from_position==$to_position );
    my $rs = $self->search({
        -and => [
            $position_column => { ($from_position>$to_position?'<':'>') => $from_position },
            $position_column => { ($from_position>$to_position?'>=':'<=') => $to_position },
        ]
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
    $self->set_column( $position_column => $self->count()+1 ) 
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

1;
__END__

=head1 TODO

Support foreign keys that cause rows to be members of mini 
positionable sets.

=head1 BUGS

If a position is not specified for an insert than a position 
will be chosen based on COUNT(*)+1.  But, it first selects the 
count then inserts the record.  The space of time between select 
and insert introduces a race condition.  To fix this we need the 
ability to lock tables in DBIC.  I've added an entry in the TODO 
about this.

=head1 AUTHOR

Aran Deltac <bluefeet@cpan.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

