package DBIx::Class::CDBICompat::HasA;

use strict;
use warnings;

sub has_a {
  my ($self, $col, $f_class, %args) = @_;
  $self->throw( "No such column ${col}" ) unless $self->_columns->{$col};
  eval "require $f_class";
  if ($args{'inflate'} || $args{'deflate'}) {
    if (!ref $args{'inflate'}) {
      my $meth = $args{'inflate'};
      $args{'inflate'} = sub { $f_class->$meth(shift); };
    }
    if (!ref $args{'deflate'}) {
      my $meth = $args{'deflate'};
      $args{'deflate'} = sub { shift->$meth; };
    }
    $self->inflate_column($col, \%args);
    return 1;
  }
  my ($pri, $too_many) = keys %{ $f_class->_primaries };
  $self->throw( "has_a only works with a single primary key; ${f_class} has more" )
    if $too_many;
  $self->add_relationship($col, $f_class,
                            { "foreign.${pri}" => "self.${col}" },
                            { _type => 'has_a', accessor => 'filter' } );
  return 1;
}

1;
