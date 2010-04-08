package # hide from PAUSE
    DBIx::Class::Componentised;

use strict;
use warnings;

use base 'Class::C3::Componentised';
use Carp::Clan qw/^DBIx::Class|^Class::C3::Componentised/;
use mro 'c3';

# this warns of subtle bugs introduced by UTF8Columns hacky handling of store_column
# if and only if it is placed before something overriding store_column
sub inject_base {
  my $class = shift;
  my ($target, @complist) = @_;

  # we already did load the component
  my $keep_checking = ! $target->isa ('DBIx::Class::UTF8Columns');

  my @target_isa = do { no strict 'refs'; @{"$target\::ISA"} };
  my $base_store_column;

  while ($keep_checking && @complist) {

    my $comp = pop @complist;

    if ($comp->isa ('DBIx::Class::UTF8Columns')) {

      $keep_checking = 0;

      $base_store_column ||=
        do { require DBIx::Class::Row; DBIx::Class::Row->can ('store_column') };

      my @broken;
      for my $existing_comp (@target_isa) {
        my $sc = $existing_comp->can ('store_column')
          or next;

        if ($sc ne $base_store_column) {
          require B;
          my $definer = B::svref_2object($sc)->STASH->NAME;
          push @broken, ($definer eq $existing_comp)
            ? $existing_comp
            : "$existing_comp (via $definer)"
          ;
        }
      }

      carp "Incorrect loading order of $comp by $target will affect other components overriding 'store_column' ("
          . join (', ', @broken)
          .'). Refer to the documentation of DBIx::Class::UTF8Columns for more info'
        if @broken;
    }

    unshift @target_isa, $comp;
  }

  $class->next::method(@_);
}

1;
