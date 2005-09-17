package DBIx::Class::Relationship::HasOne;

use strict;
use warnings;

sub has_one {
  my ($class, $acc_name, $f_class, $conds, $args) = @_;
  eval "require $f_class";
  # single key relationship
  if (not defined $conds && not defined $args) {
    my ($pri, $too_many) = keys %{ $f_class->_primaries };
    my $acc_type = ($class->_columns->{$acc_name}) ? 'filter' : 'single';
    $class->add_relationship($acc_name, $f_class,
      { "foreign.${pri}" => "self.${acc_name}" },
      { accessor => $acc_type }
    );
  }
  # multiple key relationship
  else {
    my %f_primaries = %{ $f_class->_primaries };
    my $conds_rel;
    for (keys %$conds) {
      $conds_rel->{"foreign.$_"} = "self.".$conds->{$_};
      # primary key usage checks
      if (exists $f_primaries{$_}) {
        delete $f_primaries{$_};
      }
      else
      {
        $class->throw("non primary key used in join condition: $_");
      }
    }
    $class->throw("not all primary keys used in multi key relationship!") if keys %f_primaries;
    $class->add_relationship($acc_name, $f_class,
      $conds_rel,
      { accessor => 'single' }
    );
  }
  return 1;
}

1;
