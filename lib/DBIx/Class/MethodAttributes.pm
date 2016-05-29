package # hide from PAUSE
    DBIx::Class::MethodAttributes;

use strict;
use warnings;

use DBIx::Class::_Util qw( uniq refdesc visit_namespaces );
use Scalar::Util qw( weaken refaddr );

use mro 'c3';
use namespace::clean;

my $attr_cref_registry;
sub DBIx::Class::__Attr_iThreads_handler__::CLONE {

  # This is disgusting, but the best we can do without even more surgery
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
  });

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
  my ($class,$code,@attrs) = @_;
  $class->mk_classaccessor('__attr_cache' => {})
    unless $class->can('__attr_cache');

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

  $class->__attr_cache->{$code} = [ sort( uniq(
    @{ $class->__attr_cache->{$code} || [] },
    @attrs,
  ))];

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
  return ();
}

sub FETCH_CODE_ATTRIBUTES {
  my ($class,$code) = @_;
  @{ $class->_attr_cache->{$code} || [] }
}

sub _attr_cache {
  my $self = shift;
  +{
    %{ $self->can('__attr_cache') ? $self->__attr_cache : {} },
    %{ $self->maybe::next::method || {} },
  };
}

1;
