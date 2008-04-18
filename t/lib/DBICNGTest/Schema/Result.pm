package # hide from PAUSE
 DBICNGTest::Schema::Result;
 
    use Moose;
    extends 'DBIx::Class', 'Moose::Object';
       
=head1 NAME

DBICNGTest::Schema::Result; Base Class for result and class objects

=head1 SYNOPSIS

    package DBICNGTest::Schema::Result::Member;
    
    use Moose;
    extends 'DBICNGTest::Schema::Result';
    
    ## Rest of the class definition.

=head1 DESCRIPTION

Defines the base case for loading DBIC Schemas.  We add in some additional
helpful functions for administering you schemas.  This namespace is dedicated
to integration of Moose based development practices

=head1 PACKAGE METHODS

The following is a list of package methods declared with this class.

=head2 load_components

Components to preload.

=cut

__PACKAGE__->load_components(qw/ 
    PK::Auto 
    InflateColumn::DateTime
    Core 
/);


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
    my $attrs = shift @_;
  
    my $obj = $class->SUPER::new($attrs);

    return $class->meta->new_object(
        __INSTANCE__ => $obj, %$attrs
    );
}


=head1 AUTHORS

See L<DBIx::Class> for more information regarding authors.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut


1;