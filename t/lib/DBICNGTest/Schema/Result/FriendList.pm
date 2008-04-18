package #hide from pause
 DBICNGTest::Schema::Result::FriendList;

    use Moose;
    extends 'DBICNGTest::Schema::Result';


=head1 NAME

Zoomwit::tlib::DBIC::Schema::Result::FriendList; An example Friends Class;

=head1 VERSION

0.01

=cut

our $VERSION = '0.01';


=head1 DESCRIPTION

A Person can have zero or more friends
A Person can't be their own friend
A Person over 18 can't be friends with Persons under 18 and vis versa.
A Person can have friendships that are not mutual.

=head1 ATTRIBUTES

This class defines the following attributes.

=head1 PACKAGE METHODS

This module defines the following package methods

=head2 table

Name of the Physical table in the database

=cut

__PACKAGE__
    ->table('friend_list');


=head2 add_columns

Add columns and meta information

=head3 fk_person_id

ID of the person with friends

=head3 fk_friend_id

Who is the friend?

=cut

__PACKAGE__
    ->add_columns(
        fk_person_id => {
            data_type=>'integer',
        },
        fk_friend_id => {
            data_type=>'integer',
        },
);
        

=head2 primary_key

Sets the Primary keys for this table

=cut

__PACKAGE__
    ->set_primary_key(qw/fk_person_id fk_friend_id/);
    

=head2 befriender

The person that 'owns' the friendship (list)

=cut

__PACKAGE__
    ->belongs_to( befriender => 'DBICNGTest::Schema::Result::Person', {
        'foreign.person_id' => 'self.fk_person_id' });


=head2 friendee

The actual friend that befriender is listing

=cut

__PACKAGE__
    ->belongs_to( friendee => 'DBICNGTest::Schema::Result::Person', { 
        'foreign.person_id' => 'self.fk_friend_id' });


=head1 METHODS

This module defines the following methods.

=head1 AUTHORS

See L<DBIx::Class> for more information regarding authors.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut


1;
