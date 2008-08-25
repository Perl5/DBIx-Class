package DBIx::Class::ResultSource::View;

use strict;
use warnings;

use DBIx::Class::ResultSet;

use base qw/DBIx::Class/;
__PACKAGE__->load_components(qw/ResultSource/);
__PACKAGE__->mk_group_accessors('simple' => ' is_virtual');

=head1 NAME

DBIx::Class::ResultSource::Table - Table object

=head1 SYNOPSIS

=head1 DESCRIPTION

Table object that inherits from L<DBIx::Class::ResultSource>

=head1 METHODS

=head2 is_virtual

Attribute to declare a view as virtual.

=head2 from

Returns the FROM entry for the table (i.e. the view name)
or the definition if this is a virtual view.

=cut

sub from {
  my $self = shift;
  return \"(${\$self->view_definition})" if $self->is_virtual;
  return $self->name;
}

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

With Contributions from:

Guillermo Roditi E<lt>groditi@cpan.orgE<gt>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

