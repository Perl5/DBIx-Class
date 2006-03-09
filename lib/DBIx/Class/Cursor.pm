package # hide from PAUSE 
    DBIx::Class::Cursor;

use strict;
use warnings;

sub new {
  die "Virtual method!";
}

sub next {
  die "Virtual method!";
}

sub reset {
  die "Virtual method!";
}

sub all {
  my ($self) = @_;
  $self->reset;
  my @all;
  while (my @row = $self->next) {
    push(@all, \@row);
  }
  $self->reset;
  return @all;
}

1;
