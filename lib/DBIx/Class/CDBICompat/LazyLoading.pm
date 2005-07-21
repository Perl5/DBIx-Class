package DBIx::Class::CDBICompat::LazyLoading;

use strict;
use warnings;

sub _select_columns {
  return shift->columns('Essential');
}

sub get_column {
  my ($self, $col) = @_;
  if ((ref $self) && (!exists $self->{'_column_data'}{$col})
    && $self->{'_in_database'}) {
    $self->_flesh(grep { exists $self->_column_groups->{$_}{$col}
                           && $_ ne 'All' }
                   keys %{ $self->_column_groups || {} });
  }
  $self->NEXT::get_column(@_[1..$#_]);
}

sub _flesh {
  my ($self, @groups) = @_;
  my %want;
  $want{$_} = 1 for map { keys %{$self->_column_groups->{$_}} } @groups;
  if (my @want = grep { !exists $self->{'_column_data'}{$_} } keys %want) {
    my $sth = $self->_get_sth('select', \@want, $self->_table_name,
                                $self->_ident_cond); 
    $sth->execute($self->_ident_values);
    my @val = $sth->fetchrow_array;
    foreach my $w (@want) {
      $self->{'_column_data'}{$w} = shift @val;
    }
  }
}

1;
