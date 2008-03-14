package # hide from PAUSE Indexer
    DBIx::Class::CDBICompat::AccessorMapping;

use strict;
use warnings;

sub mk_group_accessors {
  my ($class, $group, @cols) = @_;
  unless ($class->_can_accessor_name_for || $class->_can_mutator_name_for) {
    return $class->next::method($group => @cols);
  }
  foreach my $col (@cols) {
    my $ro_meth = $class->_try_accessor_name_for($col);
    my $wo_meth = $class->_try_mutator_name_for($col);

    # warn "class: $class / col: $col / ro: $ro_meth / wo: $wo_meth\n";
    if ($ro_meth eq $wo_meth or     # they're the same
        $wo_meth eq $col)           # or only the accessor is custom
    {
      $class->next::method($group => [ $ro_meth => $col ]);
    } else {
      $class->mk_group_ro_accessors($group => [ $ro_meth => $col ]);
      $class->mk_group_wo_accessors($group => [ $wo_meth => $col ]);
    }
  }
}

# CDBI 3.0.7 decided to change "accessor_name" and "mutator_name" to
# "accessor_name_for" and "mutator_name_for".  This is recent enough
# that we should support both.  CDBI does.
sub _can_accessor_name_for {
    my $class = shift;
    return $class->can("accessor_name_for") || $class->can("accessor_name");
}

sub _can_mutator_name_for {
    my $class = shift;
    return $class->can("mutator_name_for") || $class->can("mutator_name");
}

sub _try_accessor_name_for {
    my($class, $column) = @_;

    my $method = $class->_can_accessor_name_for;
    return $column unless $method;
    return $class->$method($column);
}

sub _try_mutator_name_for {
    my($class, $column) = @_;

    my $method = $class->_can_mutator_name_for;
    return $column unless $method;
    return $class->$method($column);
}


sub new {
  my ($class, $attrs, @rest) = @_;
  $class->throw_exception( "create needs a hashref" ) unless ref $attrs eq 'HASH';
  foreach my $col ($class->columns) {
    if ($class->_can_accessor_name_for) {
      my $acc = $class->_try_accessor_name_for($col);
      $attrs->{$col} = delete $attrs->{$acc} if exists $attrs->{$acc};
    }
    if ($class->_can_mutator_name_for) {
      my $mut = $class->_try_mutator_name_for($col);
      $attrs->{$col} = delete $attrs->{$mut} if exists $attrs->{$mut};
    }
  }
  return $class->next::method($attrs, @rest);
}

1;
