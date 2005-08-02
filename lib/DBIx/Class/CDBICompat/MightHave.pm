package DBIx::Class::CDBICompat::MightHave;

use strict;
use warnings;

sub might_have {
  my ($class, $rel, $f_class, @columns) = @_;
  my ($pri, $too_many) = keys %{ $class->_primaries };
  $class->throw( "might_have only works with a single primary key; ${class} has more" )
    if $too_many;
  my $f_pri;
  ($f_pri, $too_many) = keys %{ $f_class->_primaries };
  $class->throw( "might_have only works with a single primary key; ${f_class} has more" )
    if $too_many;
  $class->add_relationship($rel, $f_class,
   { "foreign.${f_pri}" => "self.${pri}" },
   { accessor => 'single', proxy => \@columns,
     cascade_update => 1, cascade_delete => 1 });
  1;
}

1;
