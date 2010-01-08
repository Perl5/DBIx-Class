package # hide from PAUSE
    DBIx::Class::Componentised;

use strict;
use warnings;

use base 'Class::C3::Componentised';
use Carp::Clan qw/^DBIx::Class|^Class::C3::Componentised/;
use mro 'c3';

# this warns of subtle bugs introduced by UTF8Columns hacky handling of store_column
sub inject_base {
  my $class = shift;
  my $target = shift;

  my @present_components = (@{mro::get_linear_isa ($target)||[]});

  no strict 'refs';
  for my $comp (reverse @_) {
    if (
      $comp->isa ('DBIx::Class::UTF8Columns')
        and
      my @broken = grep { $_ ne 'DBIx::Class::Row' and defined ${"${_}::"}{store_column} } (@present_components)
    ) {
      carp "Incorrect loading order of $comp by ${target} will affect other components overriding store_column ("
          . join (', ', @broken)
          .'). Refer to the documentation of DBIx::Class::UTF8Columns for more info';
    }
    else {
      unshift @present_components, $comp;
    }
  }

  $class->next::method($target, @_);
}

1;
