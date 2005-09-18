package DBIx::Class::Relationship::HasOne;

use strict;
use warnings;

sub might_have {
  shift->_has_one('LEFT' => @_);
}

sub has_one {
  shift->_has_one(undef => @_);
}

sub _has_one {
  my ($class, $join_type, $rel, $f_class, @columns) = @_;
  my $cond;
  if (ref $columns[0]) {
    $cond = shift @columns;
  } else {
    my ($pri, $too_many) = keys %{ $class->_primaries };
    $class->throw( "might_have/has_one can only infer join for a single primary key; ${class} has more" )
      if $too_many;
    my $f_key;
    if ($f_class->_columns->{$rel}) {
      $f_key = $rel;
    } else {
      ($f_key, $too_many) = keys %{ $f_class->_primaries };
      $class->throw( "might_have/has_one can only infer join for a single primary key; ${f_class} has more" )
        if $too_many;
    }
    $cond = { "foreign.${f_key}" => "self.${pri}" },
  }
  shift(@columns) unless defined $columns[0]; # Explicit empty condition
  my %attrs;
  if (ref $columns[0] eq 'HASH') {
    %attrs = %{shift @columns};
  }
  shift(@columns) unless defined $columns[0]; # Explicit empty attrs
  $class->add_relationship($rel, $f_class,
   $cond,
   { accessor => 'single', (@columns ? (proxy => \@columns) : ()),
     cascade_update => 1, cascade_delete => 1,
     ($join_type ? ('join_type' => $join_type) : ()),
     %attrs });
  1;
}

1;
