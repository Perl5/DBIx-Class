package DBIx::Class::AccessorGroup;

use strict;
use warnings;

use base qw/Class::Accessor::Grouped/;
use Scalar::Util qw/weaken/;
use namespace::clean;

my $successfully_loaded_components;

sub get_component_class {
  my $class = $_[0]->get_inherited($_[1]);

  if (defined $class and ! $successfully_loaded_components->{$class} ) {
    $_[0]->ensure_class_loaded($class);

    no strict 'refs';
    $successfully_loaded_components->{$class}
      = ${"${class}::__LOADED__BY__DBIC__CAG__COMPONENT_CLASS__"}
        = do { \(my $anon = 'loaded') };
    weaken($successfully_loaded_components->{$class});
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

