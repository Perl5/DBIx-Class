package DBIx::Class::SQL::Abstract;

# Many thanks to SQL::Abstract, from which I stole most of this

sub _debug { }

sub _cond_resolve {
  my ($self, $cond, $attrs, $join) = @_;
  $cond = $self->_anoncopy($cond);   # prevent destroying original
  my $ref   = ref $cond || '';
  $join   ||= $attrs->{logic} || ($ref eq 'ARRAY' ? 'OR' : 'AND');
  my $cmp   = uc($attrs->{cmp}) || '=';

  # For assembling SQL fields and values
  my(@sqlf) = ();

  # If an arrayref, then we join each element
  if ($ref eq 'ARRAY') {
    # need to use while() so can shift() for arrays
    my $subjoin;
    while (my $el = shift @$cond) {
      
      # skip empty elements, otherwise get invalid trailing AND stuff
      if (my $ref2 = ref $el) {
        if ($ref2 eq 'ARRAY') {
          next unless @$el;
        } elsif ($ref2 eq 'HASH') {
          next unless %$el;
          $subjoin ||= 'AND';
        } elsif ($ref2 eq 'SCALAR') {
          # literal SQL
          push @sqlf, $$el;
          next;
        }
        $self->_debug("$ref2(*top) means join with $subjoin");
      } else {
        # top-level arrayref with scalars, recurse in pairs
        $self->_debug("NOREF(*top) means join with $subjoin") if $subjoin;
        $el = {$el => shift(@$cond)};
      }
      my @ret = $self->_cond_resolve($el, $attrs, $subjoin);
      push @sqlf, shift @ret;
    }
  }
  elsif ($ref eq 'HASH') {
    # Note: during recursion, the last element will always be a hashref,
    # since it needs to point a column => value. So this be the end.
    for my $k (sort keys %$cond) {
      my $v = $cond->{$k};
      if ($k =~ /^-(.*)/) {
        # special nesting, like -and, -or, -nest, so shift over
        my $subjoin = $self->_modlogic($attrs, uc($1));
        $self->_debug("OP(-$1) means special logic ($subjoin), recursing...");
        my @ret = $self->_cond_resolve($v, $attrs, $subjoin);
        push @sqlf, shift @ret;
      } elsif (! defined($v)) {
        # undef = null
        $self->_debug("UNDEF($k) means IS NULL");
        push @sqlf, $self->_cond_key($attrs => $k) . ' IS NULL'
      } elsif (ref $v eq 'ARRAY') {
        # multiple elements: multiple options
        # warnings... $self->_debug("ARRAY($k) means multiple elements: [ @$v ]");
        
        # special nesting, like -and, -or, -nest, so shift over
        my $subjoin = 'OR';
        if ($v->[0] =~ /^-(.*)/) {
          $subjoin = $self->_modlogic($attrs, uc($1));    # override subjoin
          $self->_debug("OP(-$1) means special logic ($subjoin), shifting...");
          shift @$v;
        }

        # map into an array of hashrefs and recurse
        my @ret = $self->_cond_resolve([map { {$k => $_} } @$v], $attrs, $subjoin);
        
        # push results into our structure
        push @sqlf, shift @ret;        
      } elsif (ref $v eq 'HASH') {
        # modified operator { '!=', 'completed' }
        for my $f (sort keys %$v) {
          my $x = $v->{$f};
          $self->_debug("HASH($k) means modified operator: { $f }");

          # check for the operator being "IN" or "BETWEEN" or whatever
          if (ref $x eq 'ARRAY') {
            if ($f =~ /^-?\s*(not[\s_]+)?(in|between)\s*$/i) {
              my $mod = $1 ? $1 . $2 : $2;  # avoid uninitialized value warnings
              my $u = $self->_modlogic($attrs, uc($mod));
              $self->_debug("HASH($f => $x) uses special operator: [ $u ]");
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
            } else {
              # multiple elements: multiple options
              $self->_debug("ARRAY($x) means multiple elements: [ @$x ]");
  
              # map into an array of hashrefs and recurse
              my @ret = $self->_cond_resolve([map { {$k => {$f, $_}} } @$x], $attrs);

              # push results into our structure
              push @sqlf, shift @ret;              
            }
          } elsif (! defined($x)) {
            # undef = NOT null
            my $not = ($f eq '!=' || $f eq 'not like') ? ' NOT' : '';
            push @sqlf, $self->_cond_key($attrs => $k) . " IS${not} NULL";
          } else {
            # regular ol' value
            $f =~ s/^-//;   # strip leading -like =>
            $f =~ s/_/ /;   # _ => " "
            push @sqlf, join ' ', $self->_cond_key($attrs => $k), uc($f),
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

# Anon copies of arrays/hashes
sub _anoncopy {
  my ($self, $orig) = @_;
  return (ref $orig eq 'HASH' ) ? { %$orig }
     : (ref $orig eq 'ARRAY') ? [ @$orig ]
     : $orig;     # rest passthru ok
}

sub _modlogic {
  my ($self, $attrs, $sym) = @_;
  $sym ||= $attrs->{logic};
  $sym =~ tr/_/ /;
  $sym = $attrs->{logic} if $sym eq 'nest';
  return uc($sym);  # override join
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
