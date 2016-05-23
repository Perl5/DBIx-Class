package DBIx::Class::MethodAttributes;

use strict;
use warnings;

use DBIx::Class::_Util qw( uniq refdesc visit_namespaces );
use Scalar::Util qw( weaken refaddr );

use namespace::clean;

my ( $attr_cref_registry, $attr_cache_active );
sub DBIx::Class::__Attr_iThreads_handler__::CLONE {

  # This is disgusting, but the best we can do without even more surgery
  # Note the if() at the end - we do not run this crap if we can help it
  visit_namespaces( action => sub {
    my $pkg = shift;

    # skip dangerous namespaces
    return 1 if $pkg =~ /^ (?:
      DB | next | B | .+? ::::ISA (?: ::CACHE ) | Class::C3
    ) $/x;

    no strict 'refs';

    if (
      exists ${"${pkg}::"}{__cag___attr_cache}
        and
      ref( my $attr_stash = ${"${pkg}::__cag___attr_cache"} ) eq 'HASH'
    ) {
      $attr_stash->{ $attr_cref_registry->{$_}{weakref} } = delete $attr_stash->{$_}
        for keys %$attr_stash;
    }

    return 1;
  }) if $attr_cache_active;

  # renumber the cref registry itself
  %$attr_cref_registry = map {
    ( defined $_->{weakref} )
      ? (
        # because of how __attr_cache works, ugh
        "$_->{weakref}"         => $_,
      )
      : ()
  } values %$attr_cref_registry;
}

sub MODIFY_CODE_ATTRIBUTES {
  my $class = shift;
  my $code = shift;

  my $attrs;
  $attrs->{
    $_ =~ /^[a-z]+$/  ? 'builtin'
  : $_ =~ /^DBIC_/    ? 'dbic'
  :                     'misc'
  }{$_}++ for @_;


  # compaction step
  defined $attr_cref_registry->{$_}{weakref} or delete $attr_cref_registry->{$_}
    for keys %$attr_cref_registry;

  # The original misc-attr API used stringification instead of refaddr - can't change that now
  if( $attr_cref_registry->{$code} ) {
    Carp::confess( sprintf
      "Coderefs '%s' and '%s' stringify to the same value '%s': nothing will work",
      refdesc($code),
      refdesc($attr_cref_registry->{$code}{weakref}),
      "$code"
    ) if refaddr($attr_cref_registry->{$code}{weakref}) != refaddr($code);
  }
  else {
    weaken( $attr_cref_registry->{$code}{weakref} = $code )
  }


  # increment the pkg gen, this ensures the sanity checkers will re-evaluate
  # this class when/if the time comes
  mro::method_changed_in($class) if (
    ! DBIx::Class::_ENV_::OLD_MRO
      and
    ( $attrs->{dbic} or $attrs->{misc} )
  );


  # handle legacy attrs
  if( $attrs->{misc} ) {

    # if the user never tickles this - we won't have to do a gross
    # symtable scan in the ithread handler above, so:
    #
    # User - please don't tickle this
    $attr_cache_active = 1;

    $class->mk_classaccessor('__attr_cache' => {})
      unless $class->can('__attr_cache');

    $class->__attr_cache->{$code} = [ sort( uniq(
      @{ $class->__attr_cache->{$code} || [] },
      keys %{ $attrs->{misc} },
    ))];
  }


  # handle DBIC_* attrs
  if( $attrs->{dbic} ) {
    my $slot = $attr_cref_registry->{$code};

    $slot->{attrs} = [ uniq
      @{ $slot->{attrs} || [] },
      grep {
        $class->VALID_DBIC_CODE_ATTRIBUTE($_)
          or
        Carp::confess( "DBIC-specific attribute '$_' did not pass validation by $class->VALID_DBIC_CODE_ATTRIBUTE() as described in DBIx::Class::MethodAttributes" )
      } keys %{$attrs->{dbic}},
    ];
  }


  # FIXME - DBIC essentially gobbles up any attribute it can lay its hands on:
  # decidedly not cool
  #
  # There should be some sort of warning on unrecognized attributes or
  # somesuch... OTOH people do use things in the wild hence the plan of action
  # is anything but clear :/
  #
  # https://metacpan.org/source/ZIGOROU/DBIx-Class-Service-0.02/lib/DBIx/Class/Service.pm#L93-110
  # https://metacpan.org/source/ZIGOROU/DBIx-Class-Service-0.02/t/lib/DBIC/Test/Service/User.pm#L29
  # https://metacpan.org/source/ZIGOROU/DBIx-Class-Service-0.02/t/lib/DBIC/Test/Service/User.pm#L36
  #
  # For the time being reuse the old logic for any attribute we do not have
  # explicit plans for (i.e. stuff that is neither reserved, nor DBIC-internal)
  #
  # Pass the "builtin attrs" onwards, as the DBIC internals can't possibly  handle them
  return sort keys %{ $attrs->{builtin} || {} };
}

# Address the above FIXME halfway - if something (e.g. DBIC::Helpers) wants to
# add extra attributes - it needs to override this in its base class to allow
# for 'return 1' on the newly defined attributes
sub VALID_DBIC_CODE_ATTRIBUTE {
  #my ($class, $attr) = @_;

###
### !!! IMPORTANT !!!
###
### *DO NOT* yield to the temptation of using free-form-argument attributes.
### The technique was proven instrumental in Catalyst a decade ago, and
### was more recently revived in Sub::Attributes. Yet, while on the surface
### they seem immensely useful, per-attribute argument lists are in fact an
### architectural dead end.
###
### In other words: you are *very strongly urged* to ensure the regex below
### does not allow anything beyond qr/^ DBIC_method_is_ [A-Z_a-z0-9]+ $/x
###

  $_[1] =~ /^ DBIC_method_is_ (?:
    indirect_sugar
  ) $/x;
}

sub FETCH_CODE_ATTRIBUTES {
  #my ($class,$code) = @_;

  sort(
    @{ $_[0]->_attr_cache->{$_[1]} || [] },
    ( defined( $attr_cref_registry->{$_[1]}{ weakref } )
      ? @{ $attr_cref_registry->{$_[1]}{attrs} || [] }
      : ()
    ),
  )
}

sub _attr_cache {
  my $self = shift;
  +{
    %{ $self->can('__attr_cache') ? $self->__attr_cache : {} },
    %{ $self->maybe::next::method || {} },
  };
}

1;

__END__

=head1 NAME

DBIx::Class::MethodAttributes - DBIC-specific handling of CODE attributes

=head1 SYNOPSIS

 my @attrlist = attributes::get( \&My::App::Schema::Result::some_method )

=head1 DESCRIPTION

This class provides the L<DBIx::Class> inheritance chain with the bits
necessary for L<attribute|attributes> support on methods.

Historically DBIC has accepted any string as a C<CODE> attribute and made
such strings available via the semi-private L</_attr_cache> method. This
was used for e.g. the long-deprecated L<DBIx::Class::ResultSetManager>,
but also has evidence of use on both C<CPAN> and C<DarkPAN>.

Starting mid-2016 DBIC treats any method attribute starting with C<DBIC_>
as an I<internal boolean decorator> for various DBIC-related methods.
Unlike the general attribute naming policy, strict whitelisting is imposed
on attribute names starting with C<DBIC_> as described in
L</VALID_DBIC_CODE_ATTRIBUTE> below.

=head2 DBIC-specific method attributes

The following method attributes are currently recognized under the C<DBIC_*>
prefix:

=head3 DBIC_method_is_indirect_sugar

The presence of this attribute indicates a helper "sugar" method. Overriding
such methods in your subclasses will be of limited success at best, as DBIC
itself and various plugins are much more likely to invoke alternative direct
call paths, bypassing your override entirely. Good examples of this are
L<DBIx::Class::ResultSet/create> and L<DBIx::Class::Schema/connect>.

See also the check
L<DBIx::Class::Schema::SanityChecker/no_indirect_method_overrides>.

=head1 METHODS

=head2 MODIFY_CODE_ATTRIBUTES

See L<attributes/MODIFY_type_ATTRIBUTES>.

=head2 FETCH_CODE_ATTRIBUTES

See L<attributes/FETCH_type_ATTRIBUTES>. Always returns the combination of
all attributes: both the free-form strings registered via the
L<legacy system|/_attr_cache> and the DBIC-specific ones.

=head2 VALID_DBIC_CODE_ATTRIBUTE

=over

=item Arguments: $attribute_string

=item Return Value: ( true| false )

=back

This method is invoked when processing each DBIC-specific attribute (the ones
starting with C<DBIC_>). An attribute is considered invalid and an exception
is thrown unless this method returns a C<truthy> value.

=head2 _attr_cache

=over

=item Arguments: none

=item Return Value: B<purposefully undocumented>

=back

The legacy method of retrieving attributes declared on DBIC methods
(L</FETCH_CODE_ATTRIBUTES> was not defined until mid-2016). This method
B<does not return any DBIC-specific attributes>, and is kept for backwards
compatibility only.

In order to query the attributes of a particular method use
L<attributes::get()|attributes/get> as shown in the L</SYNOPSIS>.

=head1 FURTHER QUESTIONS?

Check the list of L<additional DBIC resources|DBIx::Class/GETTING HELP/SUPPORT>.

=head1 COPYRIGHT AND LICENSE

This module is free software L<copyright|DBIx::Class/COPYRIGHT AND LICENSE>
by the L<DBIx::Class (DBIC) authors|DBIx::Class/AUTHORS>. You can
redistribute it and/or modify it under the same terms as the
L<DBIx::Class library|DBIx::Class/COPYRIGHT AND LICENSE>.
