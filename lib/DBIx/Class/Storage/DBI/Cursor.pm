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
  unless ($self->{live_sth}) {
    $self->{sth}->execute(@{$self->{args} || []});
    if (my $offset = $self->{attrs}{offset}) {
      $self->{sth}->fetch for 1 .. $offset;
    }
    $self->{live_sth} = 1;
  }
  my @row = $self->{sth}->fetchrow_array;
  $self->{pos}++ if @row;
  return @row;
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
