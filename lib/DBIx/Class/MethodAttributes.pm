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
      |
    (?: bypassable | mandatory ) _resultsource_proxy
      |
    generated_from_resultsource_metadata
      |
    (?: inflated_ | filtered_ )? column_ (?: extra_)? accessor
      |
    single_relationship_accessor
      |
    (?: multi | filter ) _relationship_ (?: extra_ )? accessor
      |
    proxy_to_relationship
      |
    m2m_ (?: extra_)? sugar (?:_with_attrs)?
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

=head3 DBIC_method_is_mandatory_resultsource_proxy

=head3 DBIC_method_is_bypassable_resultsource_proxy

The presence of one of these attributes on a L<proxied ResultSource
method|DBIx::Class::Manual::ResultClass/DBIx::Class::ResultSource> indicates
how DBIC will behave when someone calls e.g.:

  $some_result->result_source->add_columns(...)

as opposed to the conventional

  SomeResultClass->add_columns(...)

This distinction becomes important when someone declares a sub named after
one of the (currently 22) methods proxied from a
L<Result|DBIx::Class::Manual::ResultClass> to
L<ResultSource|DBIx::Class::ResultSource>. While there are obviously no
problems when these methods are called at compile time, there is a lot of
ambiguity whether an override of something like
L<columns_info|DBIx::Class::ResultSource/columns_info> will be respected by
DBIC and various plugins during runtime operations.

It must be noted that there is a reason for this weird situation: during the
original design of DBIC the "ResultSourceProxy" system was established in
order to allow easy transition from Class::DBI. Unfortunately it was not
well abstracted away: it is rather difficult to use a custom ResultSource
subclass. The expansion of the DBIC project never addressed this properly
in the years since. As a result when one wishes to override a part of the
ResultSource functionality, the overwhelming practice is to hook a method
in a Result class and "hope for the best".

The subtle changes of various internal call-chains in C<DBIC v0.0829xx> make
this silent uncertainty untenable. As a solution any such override will now
issue a descriptive warning that it has been bypassed during a
C<< $rsrc->overriden_function >> invocation. A user B<must> determine how
each individual override must behave in this situation, and tag it with one
of the above two attributes.

Naturally any override marked with C<..._bypassable_resultsource_proxy> will
behave like it did before: it will be silently ignored. This is the attribute
you want to set if your code appears to work fine, and you do not wish to
receive the warning anymore (though you are strongly encouraged to understand
the other option).

However overrides marked with C<..._mandatory_resultsource_proxy> will always
be reinvoked by DBIC itself, so that any call of the form:

  $some_result->result_source->columns_info(...)

will be transformed into:

  $some_result->result_source->result_class->columns_info(...)

with the rest of the callchain flowing out of that (provided the override did
invoke L<next::method|mro/next::method> where appropriate)

=head3 DBIC_method_is_generated_from_resultsource_metadata

This attribute is applied to all methods dynamically installed after various
invocations of L<ResultSource metadata manipulation
methods|DBIx::Class::Manual::ResultClass/DBIx::Class::ResultSource>. Notably
this includes L<add_columns|DBIx::Class::ResultSource/add_columns>,
L<add_relationship|DBIx::Class::ResultSource/add_relationship>,
L<the proxied relationship attribute|DBIx::Class::Relationship::Base/proxy>
and the various L<relationship
helpers|DBIx::Class::Manual::ResultClass/DBIx::Class::Relationship>,
B<except> the L<M2M helper|DBIx::Class::Relationship/many_to_many> (given its
effects are never reflected as C<ResultSource metadata>).

=head3 DBIC_method_is_column_accessor

This attribute is applied to all methods dynamically installed as a result of
invoking L<add_columns|DBIx::Class::ResultSource/add_columns>.

=head3 DBIC_method_is_inflated_column_accessor

This attribute is applied to all methods dynamically installed as a result of
invoking L<inflate_column|DBIx::Class::InflateColumn/inflate_column>.

=head3 DBIC_method_is_filtered_column_accessor

This attribute is applied to all methods dynamically installed as a result of
invoking L<filter_column|DBIx::Class::FilterColumn/filter_column>.

=head3 DBIC_method_is_*column_extra_accessor

For historical reasons any L<Class::Accessor::Grouped> accessor is generated
twice as C<{name}> and C<_{name}_accessor>. The second method is marked with
C<DBIC_method_is_*column_extra_accessor> correspondingly.

=head3 DBIC_method_is_single_relationship_accessor

This attribute is applied to all methods dynamically installed as a result of
invoking L<might_have|DBIx::Class::Relationship/might_have>,
L<has_one|DBIx::Class::Relationship/has_one> or
L<belongs_to|DBIx::Class::Relationship/belongs_to> (though for C<belongs_to>
see L<...filter_rel...|/DBIC_method_is_filter_relationship_accessor> below.

=head3 DBIC_method_is_multi_relationship_accessor

This attribute is applied to the main method dynamically installed as a result
of invoking L<has_many|DBIx::Class::Relationship/has_many>.

=head3 DBIC_method_is_multi_relationship_extra_accessor

This attribute is applied to the two extra methods dynamically installed as a
result of invoking L<has_many|DBIx::Class::Relationship/has_many>:
C<$relname_rs> and C<add_to_$relname>.

=head3 DBIC_method_is_filter_relationship_accessor

This attribute is applied to (legacy) methods dynamically installed as a
result of invoking L<belongs_to|DBIx::Class::Relationship/belongs_to> with an
already-existing identically named column. The method is internally
implemented as an L<inflated_column|/DBIC_method_is_inflated_column_accessor>
and is labeled with both atributes at the same time.

=head3 DBIC_method_is_filter_relationship_extra_accessor

Same as L</DBIC_method_is_*column_extra_accessor>.

=head3 DBIC_method_is_proxy_to_relationship

This attribute is applied to methods dynamically installed as a result of
providing L<the proxied relationship
attribute|DBIx::Class::Relationship::Base/proxy>.

=head3 DBIC_method_is_m2m_sugar

=head3 DBIC_method_is_m2m_sugar_with_attrs

One of the above attributes is applied to the main method dynamically
installed as a result of invoking
L<many_to_many|DBIx::Class::Relationship/many_to_many>. The C<_with_atrs> suffix
serves to indicate whether the user supplied any C<\%attrs> to the
C<many_to_many> call. There is deliberately no mechanism to retrieve the actual
supplied values: if you really need this functionality you would need to rely on
L<DBIx::Class::IntrospectableM2M>.

=head3 DBIC_method_is_extra_m2m_sugar

=head3 DBIC_method_is_extra_m2m_sugar_with_attrs

One of the above attributes is applied to the extra B<four> methods dynamically
installed as a result of invoking
L<many_to_many|DBIx::Class::Relationship/many_to_many>: C<$m2m_rs>, C<add_to_$m2m>,
C<remove_from_$m2m> and C<set_$m2m>.

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
