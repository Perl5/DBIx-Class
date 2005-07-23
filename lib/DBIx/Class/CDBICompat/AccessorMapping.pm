package DBIx::Class::CDBICompat::AccessorMapping;

use strict;
use warnings;

use NEXT;

sub mk_group_accessors {
  my ($class, $group, @cols) = @_;
  unless ($class->can('accessor_name') || $class->can('mutator_name')) {
    return $class->NEXT::mk_group_accessors($group => @cols);
  }
  foreach my $col (@cols) {
    my $ro_meth = ($class->can('accessor_name')
                    ? $class->accessor_name($col)
                    : $col);
    my $wo_meth = ($class->can('mutator_name')
                    ? $class->mutator_name($col)
                    : $col);
    if ($ro_meth eq $wo_meth) {
      $class->mk_group_accessors($group => [ $ro_meth => $col ]);
    } else {
      $class->mk_group_ro_accessors($group => [ $ro_meth => $col ]);
      $class->mk_group_wo_accessors($group => [ $wo_meth => $col ]);
    }
  }
}

1;
