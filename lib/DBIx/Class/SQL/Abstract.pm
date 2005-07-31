package DBIx::Class::SQL::Abstract;

# Many thanks to SQL::Abstract, from which I stole most of this

sub _debug { }

sub _cond_resolve {
  my ($self, $cond, $attrs, $join) = @_;
  my $ref   = ref $cond || '';
  $join   ||= $attrs->{logic} || ($ref eq 'ARRAY' ? 'OR' : 'AND');
  my $cmp   = uc($attrs->{cmp}) || '=';

  # For assembling SQL fields and values
  my(@sqlf) = ();

  # If an arrayref, then we join each element
  if ($ref eq 'ARRAY') {
    # need to use while() so can shift() for arrays
    while (my $el = shift @$cond) {
      my $subjoin = 'OR';

      # skip empty elements, otherwise get invalid trailing AND stuff
      if (my $ref2 = ref $el) {
        if ($ref2 eq 'ARRAY') {
          next unless @$el;
        } elsif ($ref2 eq 'HASH') {
          next unless %$el;
          $subjoin = 'AND';
        } elsif ($ref2 eq 'SCALAR') {
          # literal SQL
          push @sqlf, $$el;
          next;
        }
        $self->_debug("$ref2(*top) means join with $subjoin");
      } else {
        # top-level arrayref with scalars, recurse in pairs
        $self->_debug("NOREF(*top) means join with $subjoin");
        $el = {$el => shift(@$cond)};
      }
      push @sqlf, scalar $self->_cond_resolve($el, $attrs, $subjoin);
    }
  }
  elsif ($ref eq 'HASH') {
    # Note: during recursion, the last element will always be a hashref,
    # since it needs to point a column => value. So this be the end.
    for my $k (sort keys %$cond) {
      my $v = $cond->{$k};
      if (! defined($v)) {
        # undef = null
        $self->_debug("UNDEF($k) means IS NULL");
        push @sqlf, $k . ' IS NULL'
      } elsif (ref $v eq 'ARRAY') {
        # multiple elements: multiple options
        $self->_debug("ARRAY($k) means multiple elements: [ @$v ]");

        # map into an array of hashrefs and recurse
        my @w = ();
        push @w, { $k => $_ } for @$v;
        push @sqlf, scalar $self->_cond_resolve(\@w, $attrs, 'OR');

      } elsif (ref $v eq 'HASH') {
        # modified operator { '!=', 'completed' }
        for my $f (sort keys %$v) {
          my $x = $v->{$f};
          $self->_debug("HASH($k) means modified operator: { $f }");

          # check for the operator being "IN" or "BETWEEN" or whatever
          if ($f =~ /^([\s\w]+)$/i && ref $x eq 'ARRAY') {
            my $u = uc($1);
            if ($u =~ /BETWEEN/) {
              # SQL sucks
              $self->throw( "BETWEEN must have exactly two arguments" ) unless @$x == 2;
              push @sqlf, join ' ',
                            $self->_cond_key($attrs => $k), $u,
                            $self->_cond_value($attrs => $k => $x->[0]),
                            'AND',
                            $self->_cond_value($attrs => $k => $x->[1]);
            } else {
              push @sqlf, join ' ', $self->_cond_key($attrs, $k), $u, '(',
                      join(', ',
                        map { $self->_cond_value($attrs, $k, $_) } @$x),
                    ')';
            }
          } elsif (ref $x eq 'ARRAY') {
            # multiple elements: multiple options
            $self->_debug("ARRAY($x) means multiple elements: [ @$x ]");

            # map into an array of hashrefs and recurse
            my @w = ();
            push @w, { $k => { $f => $_ } } for @$x;
            push @sqlf, scalar $self->_cond_resolve(\@w, $attrs, 'OR');

          } elsif (! defined($x)) {
            # undef = NOT null
            my $not = ($f eq '!=' || $f eq 'not like') ? ' NOT' : '';
            push @sqlf, $self->_cond_key($attrs => $k) . " IS${not} NULL";
          } else {
            # regular ol' value
            push @sqlf, join ' ', $self->_cond_key($attrs => $k), $f,
                          $self->_cond_value($attrs => $k => $x);
          }
        }
      } elsif (ref $v eq 'SCALAR') {
        # literal SQL
        $self->_debug("SCALAR($k) means literal SQL: $$v");
        push @sqlf, join ' ', $self->_cond_key($attrs => $k), $$v;
      } else {
        # standard key => val
        $self->_debug("NOREF($k) means simple key=val: $k ${cmp} $v");
        push @sqlf, join ' ', $self->_cond_key($attrs => $k), $cmp,
                      $self->_cond_value($attrs => $k => $v);
      }
    }
  }
  elsif ($ref eq 'SCALAR') {
    # literal sql
    $self->_debug("SCALAR(*top) means literal SQL: $$cond");
    push @sqlf, $$cond;
  }
  elsif (defined $cond) {
    # literal sql
    $self->_debug("NOREF(*top) means literal SQL: $cond");
    push @sqlf, $cond;
  }

  # assemble and return sql
  my $wsql = @sqlf ? '( ' . join(" $join ", @sqlf) . ' )' : '1 = 1';
  return wantarray ? ($wsql, @{$attrs->{bind} || []}) : $wsql; 
}

sub _cond_key {
  my ($self, $attrs, $key) = @_;
  return $key;
}

sub _cond_value {
  my ($self, $attrs, $key, $value) = @_;
  push(@{$attrs->{bind}}, $value);
  return '?';
}
  
1;

=head1 NAME 

DBIx::Class::SQL::Abstract - SQL::Abstract customized for DBIC.

=head1 SYNOPSIS

=head1 DESCRIPTION

This is a customized version of L<SQL::Abstract> for use in 
generating L<DBIx::Searchbuilder> searches.

=cut

=head1 AUTHORS

Matt S. Trout <perl-stuff@trout.me.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
