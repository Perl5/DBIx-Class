package
  DBIx::Class::SQLMaker::PostgreSQL;

use strict;
use warnings;
use base qw( DBIx::Class::SQLMaker );

sub new {
  my $self = shift;
  my %opts = (ref $_[0] eq 'HASH') ? %{$_[0]} : @_;
  push @{$opts{special_ops}}, {
    regex => qr/^with_recursive$/i,
    handler => '_with_recursive',
  };

  $self->next::method(\%opts);
}

sub _assemble_binds {
  my $self = shift;
   return map { @{ (delete $self->{"${_}_bind"}) || [] } }
   (qw/select from where with_recursive group having order limit/);
}

sub _parse_rs_attrs {
  my $self = shift;
  warn "INSIDE RS ATTRS";
  my ($rs_attrs) = @_;

  my ($cb_sql, @cb_bind) = $self->_with_recursive($rs_attrs);
  push @{$self->{with_recursive_bind}}, @cb_bind;

  my $sql = $self->next::method(@_);

  return "$cb_sql $sql";
}

sub _with_recursive {
  my ($self, $attrs) = @_;

  warn "INSIDE WITH RECURSIVE";
  my $sql = '';
  my @bind;

  if ( ref($attrs) eq 'HASH' ) {
    if ( $attrs->{'with_recursive'} ) {
      my $with_recursive = $attrs->{'with_recursive'};
      my @fields = @{$with_recursive->{'-columns'}};
      my $nrt    = $with_recursive->{'-initial'};
      my $rt     = $with_recursive->{'-recursive'};
      my $union  = $with_recursive->{'-union_all'};
#      my ($wr, @wb) = $self->_recurse_where( $attrs->{'with_recursive'} );
      my ($with_nrt_sql, @with_nrt_bind) = $nrt->as_query;
      my ($with_rt_sql, @with_rt_bind)   = $rt->as_query;
      push @bind, @with_nrt_bind;
      push @bind, @with_rt_bind;
      $sql .= $self->_sqlcase(' with recursive ') . ' temp_wr_query ' . '(' .
              join(', ', @fields) . ') ' . $self->_sqlcase('as') . ' ( ';
      $sql .= $with_nrt_sql;
      $sql .= $self->_sqlcase(' union all ') if $union;
      $sql .= $with_rt_sql;
      $sql .= ' ) ';
      warn "SQL $sql";
      return ($sql, @bind);
    }
  }

  return wantarray ? ($sql, @bind) : $sql;

}
1;
