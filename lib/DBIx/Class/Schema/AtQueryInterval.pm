package DBIx::Class::Schema::AtQueryInterval;

use Moose;

=head1 NAME

DBIx::Class::Schema::Role::AtQueryInterval; Defines a job control interval.

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

An AtQueryInterval is a plan object that will execute a certain

=head1 ATTRIBUTES

This package defines the following attributes.

=head2 job (DBIx::Class::Schema::Job)

This is the job which will run at the specified query interval

=cut

has 'job' => (
  is=>'ro',
  isa=>'DBIx::Class::Schema::Job',
  required=>1,
  handles=>['execute'],
);


=head2 interval (Int)

This is the interval we are watching for

=cut

has 'interval' => (
  is=>'ro',
  isa=>'DBIx::Class::Schema::QueryInterval',
  required=>1,
  handles=>['matches'],
);


=head1 METHODS

This module defines the following methods.

=head2 execute_if_matches ($query_count, @args)

Does the $query_count match the defined interval?  Returns a Boolean.

=cut

sub execute_if_matches {
  my ($self, $query_count, @args) = @_;
  if($self->matches($query_count)) {
  	return $self->execute(@args);
  } else {
  	return;
  }
}


=head1 AUTHORS

See L<DBIx::Class> for more information regarding authors.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut


1;