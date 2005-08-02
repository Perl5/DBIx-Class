package DBIx::Class::CDBICompat::HasA;

use strict;
use warnings;

sub has_a {
  my ($self, $col, $f_class) = @_;
  $self->throw( "No such column ${col}" ) unless $self->_columns->{$col};
  eval "require $f_class";
  my ($pri, $too_many) = keys %{ $f_class->_primaries };
  $self->throw( "has_a only works with a single primary key; ${f_class} has more" )
    if $too_many;
  $self->add_relationship($col, $f_class,
                            { "foreign.${pri}" => "self.${col}" },
                            { _type => 'has_a' } );
  $self->inflate_column($col,
    { inflate => sub { 
        my ($val, $self) = @_;
        return ($self->search_related($col, {}, {}))[0]
          || $f_class->new({ $pri => $val }); },
      deflate => sub {
        my ($val, $self) = @_;
        $self->throw("$val isn't a $f_class") unless $val->isa($f_class);
        return ($val->_ident_values)[0] } } );
  return 1;
}

1;
