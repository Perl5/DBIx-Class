package DBIx::Class::AccessorGroup;

use strict;
use warnings;

use base qw/Class::Accessor::Grouped/;

our %successfully_loaded_components;

sub get_component_class {
  my $class = $_[0]->get_inherited($_[1]);
  if (defined $class and ! $successfully_loaded_components{$class}) {
    $_[0]->ensure_class_loaded($class);
    $successfully_loaded_components{$class}++; # only increment if the load succeeded
  }
  $class;
};

sub set_component_class {
  shift->set_inherited(@_);
}

1;

=head1 NAME

DBIx::Class::AccessorGroup - See Class::Accessor::Grouped

=head1 SYNOPSIS

=head1 DESCRIPTION

This class now exists in its own right on CPAN as Class::Accessor::Grouped

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

