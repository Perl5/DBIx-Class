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

=head1 NAME 

DBIx::Class::SQL::OrderBy - Implements sorting for DBIC's SQL backend

=head1 SYNOPSIS

=head1 DESCRIPTION

This class implements the order_by attribute to L<DBIx::Class>'s search
builder.

=cut

=head1 AUTHORS

Matt S. Trout <perl-stuff@trout.me.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
