package DBIx::Class::AccessorGroup;

use strict;
use warnings;

use base qw/Class::Accessor::Grouped/;
use Scalar::Util qw/weaken blessed/;
use namespace::clean;

my $successfully_loaded_components;

sub get_component_class {
  my $class = $_[0]->get_inherited($_[1]);

  # It's already an object, just go for it.
  return $class if blessed $class;

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

=head1 AUTHOR AND CONTRIBUTORS

See L<AUTHOR|DBIx::Class/AUTHOR> and L<CONTRIBUTORS|DBIx::Class/CONTRIBUTORS> in DBIx::Class

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

