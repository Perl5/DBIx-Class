package DBIx::Class::PK::Auto;

#use base qw/DBIx::Class::PK/;
use base qw/DBIx::Class/;
use strict;
use warnings;

1;

=head1 NAME

DBIx::Class::PK::Auto - Automatic primary key class

=head1 SYNOPSIS

use base 'DBIx::Class::Core';
__PACKAGE__->set_primary_key('id');

=head1 DESCRIPTION

This class overrides the insert method to get automatically incremented primary
keys.

PK::Auto is now part of Core.

See L<DBIx::Class::Manual::Component> for details of component interactions.

=head1 LOGIC

C<PK::Auto> does this by letting the database assign the primary key field and
fetching the assigned value afterwards.

=head1 METHODS

=head2 insert

The code that was handled here is now in Row for efficiency.

=head2 sequence

The code that was handled here is now in ResultSource, and is being proxied to
Row as well.

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
