package # hide from PAUSE
    DBIx::Class::CDBICompat::ColumnCase;

use strict;
use warnings;

use base qw/DBIx::Class/;

sub _register_column_group {
  my ($class, $group, @cols) = @_;
  return $class->next::method($group => map lc, @cols);
}

sub add_columns {
  my ($class, @cols) = @_;
  $class->mk_group_accessors(column => @cols);
  $class->result_source_instance->add_columns(map lc, @cols);
}

sub has_a {
  my ($class, $col, @rest) = @_;
  $class->next::method(lc($col), @rest);
  $class->mk_group_accessors('inflated_column' => $col);
  return 1;
}

sub has_many {
  my ($class, $rel, $f_class, $f_key, @rest) = @_;
  return $class->next::method($rel, $f_class, ( ref($f_key) ?
                                                          $f_key :
                                                          lc($f_key) ), @rest);
}

sub get_inflated_column {
  my ($class, $get, @rest) = @_;
  return $class->next::method(lc($get), @rest);
}

sub store_inflated_column {
  my ($class, $set, @rest) = @_;
  return $class->next::method(lc($set), @rest);
}

sub set_inflated_column {
  my ($class, $set, @rest) = @_;
  return $class->next::method(lc($set), @rest);
}

sub get_column {
  my ($class, $get, @rest) = @_;
  return $class->next::method(lc($get), @rest);
}

sub set_column {
  my ($class, $set, @rest) = @_;
  return $class->next::method(lc($set), @rest);
}

sub store_column {
  my ($class, $set, @rest) = @_;
  return $class->next::method(lc($set), @rest);
}

sub find_column {
  my ($class, $col) = @_;
  return $class->next::method(lc($col));
}

# _build_query
#
# Build a query hash for find, et al. Overrides Retrieve::_build_query.

sub _build_query {
  my ($self, $query) = @_;

  my %new_query;
  $new_query{lc $_} = $query->{$_} for keys %$query;

  return \%new_query;
}


# CDBI will never overwrite an accessor, but it only uses one
# accessor for all column types.  DBIC uses many different
# accessor types so, for example, if you declare a column()
# and then a has_a() for that same column it must overwrite.
#
# To make this work CDBICompat has decide if an accessor
# method was put there by itself and only then overwrite.
{
  my %our_accessors;

  sub _has_custom_accessor {
    my($class, $name) = @_;
    
    no strict 'refs';
    my $existing_accessor = *{$class .'::'. $name}{CODE};
    return $existing_accessor && !$our_accessors{$existing_accessor};
  }

  sub _deploy_accessor {
    my($class, $name, $accessor) = @_;

    return if $class->_has_custom_accessor($name);

    for my $name ($name, lc $name) {
      no strict 'refs';
      no warnings 'redefine';
      *{$class .'::'. $name} = $accessor;
    }
    
    $our_accessors{$accessor}++;

    return 1;
  }
}

sub _mk_group_accessors {
  my ($class, $type, $group, @fields) = @_;

  # So we don't have to do lots of lookups inside the loop.
  my $maker = $class->can($type) unless ref $type;

  # warn "$class $type $group\n";
  foreach my $field (@fields) {
    if( $field eq 'DESTROY' ) {
        carp("Having a data accessor named DESTROY in ".
             "'$class' is unwise.");
    }

    my $name = $field;

    ($name, $field) = @$field if ref $field;

    my $accessor = $class->$maker($group, $field);
    my $alias = "_${name}_accessor";

    # warn "  $field $alias\n";
    {
      no strict 'refs';
      
      $class->_deploy_accessor($name,  $accessor);
      $class->_deploy_accessor($alias, $accessor);
    }
  }
}

sub new {
  my ($class, $attrs, @rest) = @_;
  my %att;
  $att{lc $_} = $attrs->{$_} for keys %$attrs;
  return $class->next::method(\%att, @rest);
}

1;
