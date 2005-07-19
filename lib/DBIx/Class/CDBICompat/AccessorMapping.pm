package DBIx::Class::CDBICompat::AccessorMapping;

use strict;
use warnings;

use NEXT;

sub _mk_column_accessors {
  my ($class, @cols) = @_;
  unless ($class->can('accessor_name') || $class->can('mutator_name')) {
    return $class->NEXT::_mk_column_accessors(@cols);
  }
  foreach my $col (@cols) {
    my $ro_meth = ($class->can('accessor_name')
                    ? $class->accessor_name($col)
                    : $col);
    my $wo_meth = ($class->can('mutator_name')
                    ? $class->mutator_name($col)
                    : $col);
    if ($ro_meth eq $wo_meth) {
      $class->mk_accessors($col);
    } else {
      $class->mk_ro_accessors($ro_meth);
      $class->mk_wo_accessors($wo_meth);
    }
  }
}

1;
