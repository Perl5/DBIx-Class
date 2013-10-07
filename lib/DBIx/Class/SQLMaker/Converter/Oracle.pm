package DBIx::Class::SQLMaker::Converter::Oracle;

use Data::Query::ExprHelpers;
use Moo;
use namespace::clean;

extends 'DBIx::Class::SQLMaker::Converter';

around _where_hashpair_to_dq => sub {
  my ($orig, $self) = (shift, shift);
  my ($k, $v, $logic) = @_;
  if (ref($v) eq 'HASH' and (keys %$v == 1) and lc((keys %$v)[0]) eq '-prior') {
    my $rhs = $self->_expr_to_dq((values %$v)[0]);
    return $self->_op_to_dq(
      $self->{cmp}, $self->_ident_to_dq($k), $self->_op_to_dq(PRIOR => $rhs)
    );
  } else {
    return $self->$orig(@_);
  }
};

around _apply_to_dq => sub {
  my ($orig, $self) = (shift, shift);
  my ($op, $v) = @_;
  if ($op eq 'PRIOR') {
    return $self->_op_to_dq(PRIOR => $self->_expr_to_dq($v));
  } else {
    return $self->$orig(@_);
  }
};

around _insert_to_dq => sub {
  my ($orig, $self) = (shift, shift);
  my (undef, undef, $options) = @_;
  my $dq = $self->$orig(@_);
  my $ret_count = @{$dq->{returning}};
  @{$options->{returning_container}} = (undef) x $ret_count;
  my $into = [
    map {
      my $r_dq = $dq->{returning}[$_];
      no warnings 'once';
::Dwarn($r_dq);
      local $SQL::Abstract::Converter::Cur_Col_Meta = (
        is_Identifier($r_dq)
          ? join('.', @{$r_dq->{elements}})
          : ((is_Literal($r_dq) and !ref($r_dq->{literal})
               and $r_dq->{literal} =~ /^\w+$/)
              ? $r_dq->{literal}
              : undef)
      );
      $self->_value_to_dq(\($options->{returning_container}[$_]));
    } 0..$ret_count-1
  ];
  +{ %$dq, 'Data::Query::Renderer::SQL::Dialect::ReturnInto.into' => $into };
};

1;
