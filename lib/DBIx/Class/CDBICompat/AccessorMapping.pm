package DBIx::Class::CDBICompat::AccessorMapping;

use strict;
use warnings;

use NEXT;

sub _mk_column_accessors {
  my ($class, @cols) = @_;
  unless ($class->can('accessor_name') || $class->can('mutator_name')) {
    return $class->NEXT::_mk_column_accessors('column' => @cols);
  }
  foreach my $col (@cols) {
    my $ro_meth = ($class->can('accessor_name')
                    ? $class->accessor_name($col)
                    : $col);
    my $wo_meth = ($class->can('mutator_name')
                    ? $class->mutator_name($col)
                    : $col);
    if ($ro_meth eq $wo_meth) {
      $class->mk_group_accessors('column' => $col);
    } else {
      $class->mk_group_ro_accessors('column' => $ro_meth);
      $class->mk_group_wo_accessors('column' => $wo_meth);
    }
  }
}

1;
