package DBIx::Class::AccessorGroup;

use strict;
use warnings;

use base qw( DBIx::Class::MethodAttributes Class::Accessor::Grouped );

use Scalar::Util 'blessed';
use DBIx::Class::_Util 'fail_on_internal_call';
use namespace::clean;

sub mk_classdata :DBIC_method_is_indirect_sugar {
  DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and fail_on_internal_call;
  shift->mk_classaccessor(@_);
}

sub mk_classaccessor :DBIC_method_is_indirect_sugar {
  my $self = shift;
  $self->mk_group_accessors('inherited', $_[0]);
  (@_ > 1)
    ? $self->set_inherited(@_)
    : ( DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and fail_on_internal_call )
  ;
}

sub mk_group_accessors {
  my $class = shift;
  my $type = shift;

  $class->next::method($type, @_);

  # label things
  if( $type =~ /^ ( inflated_ | filtered_ )? column $/x ) {

    $class = ref $class
      if length ref $class;

    for my $acc_pair  (
      map
        { [ $_, "_${_}_accessor" ] }
        map
          { ref $_ ? $_->[0] : $_ }
          @_
    ) {

      for my $i (0, 1) {

        my $acc_name = $acc_pair->[$i];

        attributes->import(
          $class,
          (
            $class->can($acc_name)
              ||
            Carp::confess("Accessor '$acc_name' we just created on $class can't be found...?")
          ),
          'DBIC_method_is_generated_from_resultsource_metadata',
          ($i
            ? "DBIC_method_is_${type}_extra_accessor"
            : "DBIC_method_is_${type}_accessor"
          ),
        )
      }
    }
  }
  elsif( $type eq 'inherited_ro_instance' ) {
    DBIx::Class::Exception->throw(
      "The 'inherted_ro_instance' CAG group has been retired - use 'inherited' instead"
    );
  }
}

sub get_component_class {
  my $class = $_[0]->get_inherited($_[1]);

  no strict 'refs';
  if (
    defined $class
      and
    # inherited CAG can't be set to undef effectively, so people may use ''
    length $class
      and
    # It's already an object, just go for it.
    ! defined blessed $class
      and
    ! ${"${class}::__LOADED__BY__DBIC__CAG__COMPONENT_CLASS__"}
  ) {
    $_[0]->ensure_class_loaded($class);

    ${"${class}::__LOADED__BY__DBIC__CAG__COMPONENT_CLASS__"}
      = do { \(my $anon = 'loaded') };
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
