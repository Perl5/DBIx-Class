package DBIx::Class::SQL::OrderBy;

use strict;
use warnings;

sub _cond_resolve {
  my ($self, $cond, $attrs, @rest) = @_;
  return $self->NEXT::ACTUAL::_cond_resolve($cond, $attrs, @rest)
    unless wantarray;
  my ($sql, @bind) = $self->NEXT::ACTUAL::_cond_resolve($cond, $attrs, @rest);
  if ($attrs->{order_by}) {
    $sql .= " ORDER BY ".join(', ', (ref $attrs->{order_by} eq 'ARRAY'
                                     ? @{$attrs->{order_by}}
                                     : $attrs->{order_by}));
  }
  return ($sql, @bind);
}

1;
