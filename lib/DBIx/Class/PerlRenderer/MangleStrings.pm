package DBIx::Class::PerlRenderer::MangleStrings;

use Moo;

extends 'DBIx::Class::PerlRenderer';

my %string_ops = map +($_ => 1), qw(eq ne le lt ge gt);

around _handle_op_type_binop => sub {
  my ($orig, $self) = (shift, shift);
  my ($op_name, $dq) = @_;
  if ($string_ops{$op_name}) {
    require List::Util;
    return [
      'do {',
        'my ($l, $r) = (',
          $self->_render($dq->{args}[0]),
          ',',
          $self->_render($dq->{args}[1]),
        ');',
        'my $len = List::Util::max(length($l), length($r));',
        'my ($fl, $fr) = map sprintf("%-${len}s", lc($_)), ($l, $r);',
        '$fl '.$op_name.' $fr',
      '}',
    ];
  }
  return $self->$orig(@_);
};

1;
