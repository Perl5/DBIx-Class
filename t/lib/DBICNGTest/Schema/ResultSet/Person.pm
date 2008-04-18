package # hide from pause
 DBICNGTest::Schema::ResultSet::Person;

	use Moose;
	extends 'DBICNGTest::Schema::ResultSet';


=head1 NAME

DBICNGTest::Schema::ResultSet:Person; Example Resultset

=head1 VERSION

0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

    ##Example Usage

See Tests for more example usage.

=head1 DESCRIPTION

Resultset Methods for the Person Source

=head1 ATTRIBUTES

This class defines the following attributes.

=head2 literal

a literal attribute for testing

=cut

has 'literal' => (is=>'ro', isa=>'Str', required=>1, lazy=>1, default=>'hi');


=head2 available_genders

A resultset of the genders people can have.  Keep in mind this get's run once
only at the first compile, so it's only good for stuff that doesn't change
between reboots.

=cut

has 'available_genders' => (
    is=>'ro',
    isa=>'DBICNGTest::Schema::ResultSet',
    required=>1,
    lazy=>1,
    default=> sub {
        shift
            ->result_source
            ->schema
            ->resultset('Gender');
    }
);


=head1 METHODS

This module defines the following methods.

=head2 older_than($int)

Only people over a given age

=cut

sub older_than
{
    my ($self, $age) = @_;
    
    return $self->search({age=>{'>'=>$age}});
}


=head1 AUTHORS

See L<DBIx::Class> for more information regarding authors.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut


1;
