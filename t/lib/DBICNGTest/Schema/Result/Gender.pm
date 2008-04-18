package #hide from pause
 DBICNGTest::Schema::Result::Gender;

    use Moose;
    extends 'DBICNGTest::Schema::Result';


=head1 NAME

DBICNGTest::Schema::Result::Gender; An example Gender Class;

=head1 DESCRIPTION

Tests for this type of FK relationship

=head1 ATTRIBUTES

This class defines the following attributes.

=head2 label

example of using an attribute to add constraints on a table insert

=cut

has 'label' =>(is=>'rw', required=>1, isa=>'Str');


=head1 PACKAGE METHODS

This module defines the following package methods

=head2 table

Name of the Physical table in the database

=cut

__PACKAGE__
    ->table('gender');


=head2 add_columns

Add columns and meta information

=head3 gender_id

Primary Key which is an auto generated UUID

=head3 label

Text label of the gender (ie, 'male', 'female', 'transgender', etc.).

=cut

__PACKAGE__
    ->add_columns(
        gender_id => {
            data_type=>'integer',
        },
        label => {
            data_type=>'varchar',
            size=>12,
        },
    );


=head2 primary_key

Sets the Primary keys for this table

=cut

__PACKAGE__
    ->set_primary_key(qw/gender_id/);
    
    
=head2 

Marks the unique columns

=cut

__PACKAGE__
    ->add_unique_constraint('gender_label_unique' => [ qw/label/ ]);


=head2 people

A resultset of people with this gender

=cut

__PACKAGE__
    ->has_many(
        people => 'DBICNGTest::Schema::Result::Person', 
        {'foreign.fk_gender_id' => 'self.gender_id'}
    );


=head1 METHODS

This module defines the following methods.

=head1 AUTHORS

See L<DBIx::Class> for more information regarding authors.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut


1;
