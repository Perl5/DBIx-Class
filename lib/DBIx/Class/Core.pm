package DBIx::Class::Core;

use strict;
use warnings;
no warnings 'qw';

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/
  InflateColumn
  Relationship
  PK
  Row
  TableInstance
  ResultSetInstance
  Exception
  AccessorGroup/);

1;

=head1 NAME 

DBIx::Class::Core - Core set of DBIx::Class modules.

=head1 DESCRIPTION

This class just inherits from the various modules that makes 
up the DBIx::Class core features. This makes it a convenient base
class for your DBIx::Class setup.

At the moment those are:

=over 4

=item L<DBIx::Class::InflateColumn>

=item L<DBIx::Class::Relationship>

=item L<DBIx::Class::PK>

=item L<DBIx::Class::Row>

=item L<DBIx::Class::Table>

=item L<DBIx::Class::Exception>

=item L<DBIx::Class::AccessorGroup>

=back

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

