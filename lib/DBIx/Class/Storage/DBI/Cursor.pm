package DBIx::Class::Storage::DBI::Cursor;

use base qw/DBIx::Class::Cursor/;

use strict;
use warnings;

sub new {
  my ($it_class, $sth, $args, $attrs) = @_;
  #use Data::Dumper; warn Dumper(@_);
  $it_class = ref $it_class if ref $it_class;
  my $new = {
    sth => $sth,
    args => $args,
    pos => 0,
    attrs => $attrs };
  return bless ($new, $it_class);
}

sub next {
  my ($self) = @_;
  return if $self->{attrs}{rows}
    && $self->{pos} >= $self->{attrs}{rows}; # + $self->{attrs}{offset});
  my $sth = $self->{sth};
  unless ($self->{live_sth}) {
    $sth->execute(@{$self->{args} || []});
    $self->{live_sth} = 1;
  }
  my @row = $sth->fetchrow_array;
  $self->{pos}++ if @row;
  return @row;
}

sub all {
  my ($self) = @_;
  return $self->SUPER::all if $self->{attrs}{rows};
  my $sth = $self->{sth};
  $sth->finish if $sth->{Active};
  $sth->execute(@{$self->{args} || []});
  delete $self->{live_sth};
  return @{$sth->fetchall_arrayref};
}

sub reset {
  my ($self) = @_;
  $self->{sth}->finish if $self->{sth}->{Active};
  $self->{pos} = 0;
  $self->{live_sth} = 0;
  return $self;
}

sub DESTROY {
  my ($self) = @_;
  $self->{sth}->finish if $self->{sth}->{Active};
}

1;
