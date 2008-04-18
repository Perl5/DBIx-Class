use strict;
use warnings;
use lib qw(t/lib);
use Test::More;

BEGIN {
    eval "use Moose";
    plan $@
        ? ( skip_all => 'needs Moose for testing' )
        : ( tests => 11 );
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
    => 'Query Count is zero';
    
    
=head2 cleanup

Cleanup after ourselves

=cut

unlink $db_file;


=head1 AUTHORS

See L<DBIx::Class> for more information regarding authors.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut