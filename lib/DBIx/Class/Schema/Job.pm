package DBIx::Class::Schema::Job;

use Moose;
use Moose::Util::TypeConstraints;

=head1 NAME

DBIx::Class::Schema::Job; A job associated with a Schema

=head1 SYNOPSIS

The following example creates a new job and then executes it.

    my $job = DBIx::Class::Schema->new(runs => sub { print 'did job'});
    $job->execute; # 'did job' -> STDOUT

=head1 DESCRIPTION

This is a base class intended to hold code that get's executed by the schema
according to rules known to the schema.  Subclassers may wish to override how
the L</runs> attribute is defined in order to create custom behavior.

=head1 SUBTYPES

This package defines the following subtypes

=head2 Handler

A coderef based type that the job runs when L</execute> is called.

=cut

subtype 'DBIx::Class::Schema::Job::Handler'
    => as 'CodeRef';
    
coerce 'DBIx::Class::Schema::Job::Handler'
    => from 'Str'
    => via {
    	my $handler_method = $_; 
        sub {
        	my $job = shift @_;
        	my $target = shift @_;
        	$target->$handler_method($job, @_);
        };                 
    };

=head1 ATTRIBUTES

This package defines the following attributes.

=head2 runs

This is a coderef which is de-reffed by L</execute> and is passed the job object
(ie $self), and any additional arguments passed to L</execute>

=cut

has 'runs' => (
  is=>'ro',
  isa=>'DBIx::Class::Schema::Job::Handler',
  coerce=>1,
  required=>1,
);


=head1 METHODS

This module defines the following methods.

=head2 execute ($schema, $query_interval)

Method called by the L<DBIx::Class::Schema> when it wants a given job to run.

=cut

sub execute {
	return $_[0]->runs->(@_);
}


=head1 AUTHORS

See L<DBIx::Class> for more information regarding authors.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut


1;