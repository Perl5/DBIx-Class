package DBIx::Class::Schema::QueryInterval;

use Moose;

=head1 NAME

DBIx::Class::Schema::Role::QueryInterval; Defines a job control interval.

=head1 SYNOPSIS

The following example shows how to define a job control interval and assign it
to a particular L<DBIx::Class::Schema::Job> for a L<DBIx::Class::Schema>

    my $job = DBIx::Class::Schema->new(runs => sub { print 'did job'});
    my $interval = DBIx::Class::Schema::Interval->new(every => 10);
    
    if($interval->matches($query_count)) {
    	print "I indentified the query count as matching";
    }
    
    ## $schema->isa(DBIx::Class::Schema);
    $schema->create_and_add_at_query_intervals($interval => $job);
    
=head1 DESCRIPTION

A Query Interval defines a reoccuring period based on the query count from a
given offset.  For example, you can define a query interval of 10 queries
with an offset of 1 query.  This interval identifies query number 11, 21, 31,
and so on.

=head1 ATTRIBUTES

This package defines the following attributes.

=head2 every (Int)

This is the 'size' of the gap identifying a query as matching a particular
interval.  Think, "I match every X queries".

=cut

has 'every' => (
  is=>'ro',
  isa=>'Int',
  required=>1,
);


=head2 offset (Int)

This is a number of queries from the start of all queries to offset the match
counting mechanism.  This is basically added to the L</every> attribute to 
identify a query as matching the interval we wish to define.

=cut

has 'offset' => (
  is=>'ro',
  isa=>'Int',
  required=>1,
  default=>0,
);


=head1 METHODS

This module defines the following methods.

=head2 matches ($query_count)

Does the $query_count match the defined interval?  Returns a Boolean.

=cut

sub matches {
  my ($self, $query_count) = @_;
  my $offset_count = $query_count - $self->offset;
  return $offset_count % $self->every ? 0:1;
}


=head1 AUTHORS

See L<DBIx::Class> for more information regarding authors.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut


1;