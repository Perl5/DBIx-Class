package DBIx::Class::Table;

use strict;
use warnings;

use DBIx::Class::ResultSet;

use Carp qw/croak/;

use base qw/DBIx::Class/;
__PACKAGE__->load_components(qw/ResultSource AccessorGroup/);

__PACKAGE__->mk_group_accessors('simple' =>
  qw/_columns _primaries name resultset_class result_class schema/);

=head1 NAME 

DBIx::Class::Table - Table object

=head1 SYNOPSIS

=head1 DESCRIPTION

Table object that inherits from L<DBIx::Class::ResultSource>

=head1 METHODS

=head2 from

Returns the FROM entry for the table (i.e. the table name)

=cut

sub from { shift->name; }

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

