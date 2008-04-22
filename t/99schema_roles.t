use strict;
use warnings;
use lib qw(t/lib);
use Test::More;

BEGIN {
    eval "use Moose";
    plan $@
        ? ( skip_all => 'needs Moose for testing' )
        : ( tests => 35 );
}

=head1 NAME

DBICNGTest::Schema::ResultSet:Person; Example Resultset

=head1 DESCRIPTION

Tests for the various Schema roles you can either use or apply

=head1 TESTS

=head2 initialize database

create a schema and setup

=cut

use_ok 'DBICNGTest::Schema';

ok my $db_file = Path::Class::File->new(qw/t var DBIxClassNG.db/)
    => 'created a path for the test database';

unlink $db_file;

ok my $schema = DBICNGTest::Schema->connect_and_setup($db_file)
    => 'Created a good Schema';

is ref $schema->source('Person'), 'DBIx::Class::ResultSource::Table'
    => 'Found Expected Person Source';
    
is $schema->resultset('Person')->count, 5
    => 'Got the correct number of people';

is $schema->resultset('Gender')->count, 3
    => 'Got the correct number of genders';


=head2 check query counter

Test the query counter role

=cut

use_ok 'DBIx::Class::Storage::DBI::Role::QueryCounter';
DBIx::Class::Storage::DBI::Role::QueryCounter->meta->apply($schema->storage);

is $schema->storage->query_count, 0
    => 'Query Count is zero';
    
is $schema->resultset('Person')->find(1)->name, 'john'
    => 'Found John!';

is $schema->resultset('Person')->find(2)->name, 'dan'
    => 'Found Dan!';

is $schema->storage->query_count, 2
    => 'Query Count is two';


=head2 check at query interval 
    
Test the role for associating events with a given query interval

=cut

use_ok 'DBIx::Class::Schema::Role::AtQueryInterval';
DBIx::Class::Schema::Role::AtQueryInterval->meta->apply($schema);

ok my $job1 = $schema->create_job(runs=>sub { 'hello'})
    => 'Created a job';

is $job1->execute, 'hello',
    => 'Got expected information from the job';

ok my $job2 = $schema->create_job(runs=>'job_handler_echo')
    => 'Created a job';

is $job2->execute($schema, 'hello1'), 'hello1',
    => 'Got expected information from the job';

ok my $interval1 = $schema->create_query_interval(every=>10)
    => 'Created a interval';

ok $interval1->matches(10)
    => 'correctly matched 10';

ok $interval1->matches(20)
    => 'correctly matched 20';

ok !$interval1->matches(22)
    => 'correctly didnt matched 22';

ok my $interval2 = $schema->create_query_interval(every=>10, offset=>2)
    => 'Created a interval';

ok $interval2->matches(12)
    => 'correctly matched 12';

ok $interval2->matches(22)
    => 'correctly matched 22';

ok !$interval2->matches(25)
    => 'correctly didnt matched 25';
    
ok my $at = $schema->create_at_query_interval(interval=>$interval2, job=>$job2)
    => 'created the at query interval object';
    
is $at->execute_if_matches(32, $schema, 'hello2'), 'hello2'
    => 'Got correct return';
    
ok $schema->at_query_intervals([$at])
    => 'added job to run at a given interval';

is_deeply [$schema->execute_jobs_at_query_interval(42, 'hello4')], ['hello4']
    => 'got expected job return value';
    
=head2 create jobs via express method

Using the express method, build a bunch of jobs

=cut

ok my @ats = $schema->create_and_add_at_query_intervals(

    {every => 10} => {
        runs => sub {10},
    },
    {every => 20} => {
        runs => sub {20},
    },
    {every => 30} => {
        runs => sub {30},
    },
    {every => 101} => [
        {runs => sub {101.1}},
        {runs => sub {101.2}},       
    ],
           
) => 'created express method at query intervals';


is_deeply [$schema->execute_jobs_at_query_interval(10)], [10]
    => 'Got Expected return for 10';

is_deeply [$schema->execute_jobs_at_query_interval(12, 'hello5')], ['hello5']
    => 'Got Expected return for 12';
       
is_deeply [$schema->execute_jobs_at_query_interval(20)], [10,20]
    => 'Got Expected return for 20';

is_deeply [$schema->execute_jobs_at_query_interval(30)], [10,30]
    => 'Got Expected return for 30';
    
is_deeply [$schema->execute_jobs_at_query_interval(60)], [10,20,30]
    => 'Got Expected return for 60';    
     
is_deeply [$schema->execute_jobs_at_query_interval(101)], [101.1,101.2]
    => 'Got Expected return for 101';
    
    
=head2 cleanup

Cleanup after ourselves

=cut

unlink $db_file;


=head1 AUTHORS

See L<DBIx::Class> for more information regarding authors.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut