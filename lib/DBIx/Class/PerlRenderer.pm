package DBIx::Class::PerlRenderer;

use B qw(perlstring);
use Moo;
use namespace::clean;

extends 'Data::Query::Renderer::Perl';

around _render_identifier => sub {
  my ($orig, $self) = (shift, shift);
  my $dq = +{ %{$_[0]}, elements => [ @{$_[0]->{elements}} ] };
  my $last = pop @{$dq->{elements}};
  [ $self->$orig($dq)->[0].'->get_column('.perlstring($last).')' ];
};

1;
