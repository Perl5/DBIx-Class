package #hide from pause
 DBICNGTest::Schema::Result::Person;

    use Moose;
    use DateTime;
    extends 'DBICNGTest::Schema::Result';


=head1 NAME

DBICNGTest::Schema::Result::Person; An example Person Class;

=head1 DESCRIPTION

Tests for this type of FK relationship

=head1 ATTRIBUTES

This class defines the following attributes.

=head2 created

attribute for the created column

=cut

has 'created' => (
    is=>'ro',
    isa=>'DateTime',
    required=>1,
    default=>sub {
    	DateTime->now;
    },
);


=head1 PACKAGE METHODS

This module defines the following package methods

=head2 table

Name of the Physical table in the database

=cut

__PACKAGE__
    ->table('person');


=head2 add_columns

Add columns and meta information

=head3 person_id

Primary Key which is an auto generated autoinc

=head3 fk_gender_id

foreign key to the Gender table

=head3 name

Just an ordinary name

=head3 age

The person's age

head3 created

When the person was added to the database

=cut

__PACKAGE__
    ->add_columns(
        person_id => {
            data_type=>'integer',
        },
        fk_gender_id => {
            data_type=>'integer',
        },      
        name => {
            data_type=>'varchar',
            size=>32,
        },
        age => {
            data_type=>'integer',
            default_value=>25,
        },
        created => {
            data_type=>'datetime',
            default_value=>'date("now")',
        });


=head2 primary_key

Sets the Primary keys for this table

=cut

__PACKAGE__
    ->set_primary_key(qw/person_id/);


=head2 friendlist

Each Person might have a resultset of friendlist 

=cut

__PACKAGE__
    ->has_many( 
        friendlist => 'DBICNGTest::Schema::Result::FriendList',
        {'foreign.fk_person_id' => 'self.person_id'});
    

=head2 gender

This person's gender

=cut

__PACKAGE__
    ->belongs_to( gender => 'DBICNGTest::Schema::Result::Gender', { 
        'foreign.gender_id' => 'self.fk_gender_id' });
        

=head2 fanlist

A resultset of the people listing me as a friend (if any)

=cut

__PACKAGE__
    ->belongs_to( fanlist => 'DBICNGTest::Schema::Result::FriendList', { 
        'foreign.fk_friend_id' => 'self.person_id' });


=head2 friends

A resultset of Persons who are in my FriendList

=cut

__PACKAGE__
    ->many_to_many( friends => 'friendlist', 'friend' );
    

=head2 fans

A resultset of people that have me in their friendlist

=cut

__PACKAGE__
    ->many_to_many( fans => 'fanlist', 'befriender' );


=head1 METHODS

This module defines the following methods.

=head1 AUTHORS

See L<DBIx::Class> for more information regarding authors.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut


1;
