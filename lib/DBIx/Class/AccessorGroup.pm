package DBIx::Class::AccessorGroup;

use strict;
use warnings;

use base qw/Class::Accessor::Grouped/;
use mro 'c3';

use Scalar::Util qw/weaken blessed/;
use DBIx::Class::_Util 'fail_on_internal_call';
use namespace::clean;

sub mk_classdata {
  DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and fail_on_internal_call;
  shift->mk_classaccessor(@_);
}

sub mk_classaccessor {
  my $self = shift;
  $self->mk_group_accessors('inherited', $_[0]);
  (@_ > 1)
    ? $self->set_inherited(@_)
    : ( DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and fail_on_internal_call )
  ;
}

my $successfully_loaded_components;

sub get_component_class {
  my $class = $_[0]->get_inherited($_[1]);

  # It's already an object, just go for it.
  return $class if blessed $class;

  if (defined $class and ! $successfully_loaded_components->{$class} ) {
    $_[0]->ensure_class_loaded($class);

    mro::set_mro( $class, 'c3' );

    no strict 'refs';
    $successfully_loaded_components->{$class}
      = ${"${class}::__LOADED__BY__DBIC__CAG__COMPONENT_CLASS__"}
        = do { \(my $anon = 'loaded') };
    weaken($successfully_loaded_components->{$class});
  }

  $class;
};

sub set_component_class {
  $_[0]->set_inherited($_[1], $_[2]);

  # trigger a load for the case of $foo->component_accessor("bar")->new
  $_[0]->get_component_class($_[1])
    if defined wantarray;
}

1;

=head1 NAME

DBIx::Class::AccessorGroup - See Class::Accessor::Grouped

=head1 SYNOPSIS

=head1 DESCRIPTION

This class now exists in its own right on CPAN as Class::Accessor::Grouped

=head1 FURTHER QUESTIONS?

Check the list of L<additional DBIC resources|DBIx::Class/GETTING HELP/SUPPORT>.

=head1 COPYRIGHT AND LICENSE

This module is free software L<copyright|DBIx::Class/COPYRIGHT AND LICENSE>
by the L<DBIx::Class (DBIC) authors|DBIx::Class/AUTHORS>. You can
redistribute it and/or modify it under the same terms as the
L<DBIx::Class library|DBIx::Class/COPYRIGHT AND LICENSE>.

=cut
