package DBIx::Class::SQLMaker::Converter::MySQL;

use Data::Query::ExprHelpers;
use Moo;
use namespace::clean;

extends 'DBIx::Class::SQLMaker::Converter';

foreach my $type (qw(update delete)) {
  around "_${type}_to_dq" => sub {
    my ($orig, $self) = (shift, shift);
    $self->_mangle_mutation_dq($self->$orig(@_));
  };
}

sub _mangle_mutation_dq {
  my ($self, $dq) = @_;
  my $target = $dq->{target};
  my $target_name_re = do {
    if (is_Identifier $target) {
      join("\\.", map "(?:\`\Q$_\E\`|\Q$_\E)", @{$target->{elements}})
    } elsif (
      is_Literal $target
      and $target->{literal}
      and $target->{literal} =~ /^(?:\`([^`]+)\`|([\w\-]+))$/
    ) {
      map "\`\Q$_\E\`|\Q$_\E", (defined $1) ? $1 : $2;
    } else {
      undef
    }
  };
  return $dq unless defined $target_name_re;
  my $match_re = "SELECT(.*(?:FROM|JOIN)\\s+)${target_name_re}(.*)";
  my $selectify = sub {
    my ($before, $after, $values) = @_;
    $before =~ s/FROM\s+(.*)//i;
    my $from_before = $1;
    return Select(
      [ Literal('SQL' => $before) ],
      Literal('SQL' => [
        Literal('SQL' => $from_before),
        $target,
        Literal('SQL' => $after, $values)
      ])
    );
  };
  map_dq_tree {
    if (is_Literal) {
      if ($_->{literal} =~ /^${match_re}$/i) {
        return \$selectify->($1, $2, $_->{values});
      }
      if ($_->{literal} =~ /\(\s*SELECT\s+/i) {
        require Text::Balanced;
        my $remain = $_->{literal};
        my $before = '';
        my @parts;
        while ($remain =~ s/^(.*?)(\(\s*SELECT\s+.*)$/$2/i) {
          $before .= $1;
          (my ($select), $remain) = do {
            # idiotic design - writes to $@ but *DOES NOT* throw exceptions
            local $@;
            Text::Balanced::extract_bracketed( $remain, '()', qr/[^\(]*/ );
          };
          return $_ unless $select; # balanced failed, give up
          if ($select =~ /^\(\s*${match_re}\s*\)$/i) {
            my $sel_dq = $selectify->($1, $2);
            push @parts, Literal(SQL => "${before}("), $sel_dq;
            $before = ')';
          } else {
            $before .= $select;
          }
        }
        if (@parts) {
          push @parts, Literal(SQL => $before.$remain, $_->{values});
          return \Literal(SQL => \@parts);
        }
      }
    }
    $_
  } $dq;
};

around _generate_join_node => sub {
  my ($orig, $self) = (shift, shift);
  my $node = $self->$orig(@_);
  my $to_jt = ref($_[0][0]) eq 'ARRAY' ? $_[0][0][0] : $_[0][0];
  if (ref($to_jt) eq 'HASH' and ($to_jt->{-join_type}||'') =~ /^STRAIGHT\z/i) {
    $node->{'Data::Query::Renderer::SQL::MySQL.straight_join'} = 1;
  }
  return $node;
};

1;
