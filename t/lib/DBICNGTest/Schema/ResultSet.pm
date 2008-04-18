package # hide from PAUSE
 DBICNGTest::Schema::ResultSet;
 
    use Moose;
    extends 'DBIx::Class::ResultSet', 'Moose::Object';
       
=head1 NAME

DBICNGTest::Schema::ResultSet; A base ResultSet Class

=head1 SYNOPSIS

    package DBICNGTest::Schema::ResultSet::Member;
    
    use Moose;
    extends 'DBICNGTest::Schema::ResultSet';
    
    ## Rest of the class definition.

=head1 DESCRIPTION

All ResultSet classes will inherit from this.  This provides some base function
for all your resultsets and it is also the default resultset if you don't
bother to declare a custom resultset in the resultset namespace

=head1 PACKAGE METHODS

The following is a list of package methods declared with this class.

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


=head1 AUTHORS

See L<DBIx::Class> for more information regarding authors.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut


1;