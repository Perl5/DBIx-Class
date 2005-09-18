package DBIx::Class::CDBICompat::MightHave;

use strict;
use warnings;

sub might_have {
  my ($class, $rel, $f_class, @columns) = @_;
  if (ref $columns[0] || !defined $columns[0]) {
    return $class->NEXT::might_have($rel, $f_class, @columns);
  } else {
    return $class->NEXT::might_have($rel, $f_class, undef,
                                     { proxy => \@columns });
  }
}

1;
