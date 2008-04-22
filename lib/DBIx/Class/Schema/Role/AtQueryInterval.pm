package DBIx::Class::Schema::Role::AtQueryInterval;

use Moose::Role;
use MooseX::AttributeHelpers;
use DBIx::Class::Schema::Job;
use DBIx::Class::Schema::QueryInterval;
use DBIx::Class::Schema::AtQueryInterval;

=head1 NAME

DBIx::Class::Schema::Role::AtQueryInterval; Execute code at query intervals

=head1 SYNOPSIS

The follow will execute the 'do_something' method each and every 10 queries,
excute a subref each 20 queries, and do both each 30 queries.  This first
example is the long, hard way.
    
    ## ISA DBIx::Class::Schema::Job
    
    my $job1 = $schema->create_job(
        runs => 'do_something',
    );
 
    my $job2 = $schema->create_job(
        runs => sub {warn 'queries counted'},
    );
    
    
    ## ISA DBIx::Class::Schema::QueryInterval
    
    my $interval_10 = $schema->create_query_interval(every => 10);
    my $interval_20 = $schema->create_query_interval(every => 20);
    my $interval_30 = $schema->create_query_interval(every => 30);
    
    
    ## USA DBIx::Class::Schema::AtQueryInterval
       
    my $at1 = $schema->create_at_query_interval(
        interval => $interval_10, job => $job1,
    );

    my $at2 = $schema->create_at_query_interval(
        interval => $interval_20, job => $job2,
    );
    
    my $at3 = $schema->create_at_query_interval(
        interval => $interval_30, job=>$job1,
    );

    my $at4 = $schema->create_at_query_interval(
        interval => $interval_30, job=>$job2,
    );
    
    $schema->query_intervals([$1, $at2, $at3, $at4]);
    
Or you can take the express trip (assuming you are not creating any custom
Query Intervals, Jobs, etc.)  Notice that this method allows jobs to be defined
as an arrayref to make it easier to defined multiple jobs for a given interval.

In order to perform the needed object instantiation, this class will use the
methods 'query_interval_class', 'job_class' and 'at_query_interval_class'.

    $schema->create_and_add_at_query_intervals(
        {every => 10} => {
        	runs => 'do_something',
        },
        {every => 20} => {
            runs => sub {
            	warn 'queries counted';
            },
        },        
        {every => 30} => [
            {runs => 'do_something'}, 
            {runs => sub{
            	warn 'queries counted';
            }},        
        ],
    );

All the above sit in a DBIx::Class::Schema that consumes the proper roles and 
defines a function which receives three arguments:
    
    sub do_something {
    	my ($job, $schema, $at_query_interval) = @_;
    }

=head1 DESCRIPTION

Sometime you'd like to perform certain housekeeping activities at preset query
intervals.  For example, every 100 queries you want to update a reporting table
that contains denormalized information.  This role allows you to assign a
scalar containing the name of a method in your schema class, an anonymous sub,
or an arrayref of either to a particular interval.

=head1 ATTRIBUTES

This package defines the following attributes.

=head2 query_interval_class

The default class used to create an interval class from a hash of initializing
information.

=cut

has 'query_interval_class' => (
  is=>'ro',
  isa=>'ClassName',
  required=>1,
  default=>'DBIx::Class::Schema::QueryInterval',
  handles=> {
  	'create_query_interval' => 'new',
  },
);


=head2 job_class

The default class used to create an job class from a hash of initializing
information.

=cut

has 'job_class' => (
  is=>'ro',
  isa=>'ClassName',
  required=>1,
  default=>'DBIx::Class::Schema::Job',
  handles=> {
    'create_job' => 'new',
  },
);


=head2 at_query_interval_class

The default class used to create an job class from a hash of initializing
information.

=cut

has 'at_query_interval_class' => (
  is=>'ro',
  isa=>'ClassName',
  required=>1,
  default=>'DBIx::Class::Schema::AtQueryInterval',
  handles=> {
    'create_at_query_interval' => 'new',
  },
);


=head2 at_query_intervals

This is an arrayref of L<DBIx::Class::Schema::AtQueryInterval> objects which 
holds all the jobs that need to be run at the given interval.

=cut

has 'at_query_intervals' => (
  is=>'rw',
  metaclass => 'Collection::Array',
  auto_deref => 1,
  isa=>'ArrayRef[DBIx::Class::Schema::AtQueryInterval]',
  provides => {
  	push => 'add_at_query_interval',
  },
);


=head1 METHODS

This module defines the following methods.

=head2 execute_jobs_at_query_interval ($int)

Execute all the jobs which match the given interval

=cut

sub execute_jobs_at_query_interval {
  my ($self, $query_count, @args) = @_;
  my @responses;
  foreach my $at ($self->at_query_intervals) {
  	push @responses,
  	  $at->execute_if_matches($query_count, $self, @args);
  }
  return @responses;
}


=head2 create_and_add_at_query_intervals (%definitions)

Uses the shortcut method shown above to quickly build a plan from a simple perl
array of hashes.

=cut

sub create_and_add_at_query_intervals {
  my ($self, @definitions) = @_;
  while (@definitions) {
  	my $interval = $self->normalize_query_interval(shift @definitions);
    my @jobs = $self->normalize_to_jobs(shift @definitions);
    foreach my $job (@jobs) {
      my $at = $self->create_at_query_interval(interval=>$interval, job=>$job);
	  $self->add_at_query_interval($at);  
    }		
  }
}


=head2 normalize_query_interval ($hash||$obj)

Given an argument, make sure it's a L<DBIx::Class::Schema::QueryInterval>,
coercing it if neccessary.

=cut

sub normalize_query_interval {
  my ($self, $arg) = @_;
  if(blessed $arg && $arg->isa('DBIx::Class::Schema::QueryInterval')) {
  	return $arg;
  } else {
  	return $self->create_query_interval($arg);
  }
}

=head2 normalize_to_jobs ($hash||$obj||$arrayref)

Incoming jobs need to be normalized to an array, so that we can handle adding
multiple jobs per interval.

=cut

sub normalize_to_jobs {
  my ($self, $arg) = @_;
  my @jobs = ref $arg eq 'ARRAY' ? @$arg : ($arg);
  return map {$self->normalize_job($_)} @jobs;
}


=head2 normalize_job ($hash||$obj)

Given an argument, make sure it's a L<DBIx::Class::Schema::Job>,
coercing it if neccessary.

=cut

sub normalize_job {
  my ($self, $arg) = @_;
  if(blessed $arg && $arg->isa('DBIx::Class::Schema::Job')) {
    return $arg;
  } else {
    return $self->create_job($arg);
  }
}


=head1 AUTHORS

See L<DBIx::Class> for more information regarding authors.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut


1;