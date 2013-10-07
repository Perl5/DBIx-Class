package DBIx::Class::SQLMaker::Renderer::Access;

use Moo;
use namespace::clean;

extends 'Data::Query::Renderer::SQL::Naive';

around _render_join => sub {
  my ($orig, $self) = (shift, shift);
  my ($dq) = @_;
  local $dq->{outer} = 'INNER' if $dq->{on} and !$dq->{outer};
  [ '(', @{$self->$orig(@_)}, ')' ];
};

1;
