package # hide from PAUSE
 DBICNGTest::Schema;
   
	use Moose;
	use Path::Class::File;
    extends 'DBIx::Class::Schema',  'Moose::Object'; 


=head1 NAME

DBICNGTest::Schema; Schema Base For Testing Moose Roles, Traits, etc.

=head1 SYNOPSIS

    my $schema = DBICNGTest::Schema->connect($dsn);
    
    ## Do anything you would as with a normal $schema object.

=head1 DESCRIPTION

Defines the base case for loading DBIC Schemas.  We add in some additional
helpful functions for administering you schemas.  This namespace is dedicated
to integration of Moose based development practices.

=head1 PACKAGE METHODS

The following is a list of package methods declared with this class.

=head2 load_namespaces

Automatically load the classes and resultsets from their default namespaces.

=cut

__PACKAGE__->load_namespaces(
    default_resultset_class => 'ResultSet',
);


=head1 ATTRIBUTES

This class defines the following attributes.

=head1 METHODS

This module declares the following methods

=head2 new

overload new to make sure we get a good meta object and that the attributes all
get properly setup.  This is done so that our instances properly get a L<Moose>
meta class.

=cut

sub new
{
    my $class = shift @_;
    my $obj = $class->SUPER::new(@_);
  
    return $class->meta->new_object(
        __INSTANCE__ => $obj, @_
    );
}


=head2 connect_and_setup

Creates a schema, deploys a database and sets the testing data.

=cut

sub connect_and_setup {
    my $class = shift @_;
    my $db_file = shift @_;
    
    my ($dsn, $user, $pass) = (
      $ENV{DBICNG_DSN} || "dbi:SQLite:${db_file}",
      $ENV{DBICNG_USER} || '',
      $ENV{DBICNG_PASS} || '',
    );
    
    return $class
        ->connect($dsn, $user, $pass, { AutoCommit => 1 })
        ->setup;
}


=head2 setup

deploy a database and populate it with the initial data

=cut

sub setup {
    my $self = shift @_;
    $self->deploy();
    $self->initial_populate(@_);
    
    return $self;
}


=head2 initial_populate

initializing the startup database information

=cut

sub initial_populate {
    my $self = shift @_;
    
    my @genders = $self->populate('Gender' => [
        [qw(gender_id label)],
        [qw(1 female)],
        [qw(2 male)],
        [qw(3 transgender)],
    ]);
  
    my @persons = $self->populate('Person' => [
        [ qw(person_id fk_gender_id name age) ],
        [ qw(1 1 john 25) ],
        [ qw(2 1 dan 35) ],
        [ qw(3 2 mary 15) ],
        [ qw(4 2 jane 95) ],
        [ qw(5 3 steve 40) ], 
    ]);
    
    my @friends = $self->populate('FriendList' => [
        [ qw(fk_person_id fk_friend_id) ],
        [ qw(1 2) ],
        [ qw(1 3) ],   
        [ qw(2 3) ], 
        [ qw(3 2) ],             
    ]);
}


=head1 AUTHORS

See L<DBIx::Class> for more information regarding authors.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut


1;
