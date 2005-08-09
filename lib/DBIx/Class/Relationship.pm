package DBIx::Class::Relationship;

use strict;
use warnings;

use base qw/DBIx::Class Class::Data::Inheritable/;

__PACKAGE__->load_own_components(qw/Accessor CascadeActions ProxyMethods Base/);

__PACKAGE__->mk_classdata('_relationships', { } );

=head1 NAME 

DBIx::Class::Relationship - Inter-table relationships

=head1 SYNOPSIS

=head1 DESCRIPTION

This class handles relationships between the tables in your database
model. It allows your to set up relationships, and to perform joins
on searches.

=head1 METHODS

=over 4

=cut

1;

=back

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

