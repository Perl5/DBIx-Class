package DBIx::Class::ResultSet;

use strict;
use warnings;
use overload
        '0+'     => 'count',
        fallback => 1;

sub new {
  my ($it_class, $db_class, $cursor, $args, $cols, $attrs) = @_;
  #use Data::Dumper; warn Dumper(@_);
  $it_class = ref $it_class if ref $it_class;
  $attrs = { %{ $attrs || {} } };
  unless ($cursor) {
    $attrs->{bind} = $args;
    $cursor = $db_class->storage->select($db_class->_table_name,$cols,
                                        $attrs->{where},$attrs);
  }
  my $new = {
    class => $db_class,
    cursor => $cursor,
    cols => $cols,
    args => $args,
    cond => $attrs->{where},
    attrs => $attrs };
  return bless ($new, $it_class);
}

sub slice {
  my ($self, $min, $max) = @_;
  my $attrs = { %{ $self->{attrs} || {} } };
  $self->{class}->throw("Can't slice without where") unless $attrs->{where};
  $attrs->{offset} = $min;
  $attrs->{rows} = ($max ? ($max - $min + 1) : 1);
  my $slice = $self->new($self->{class}, undef, $self->{args},
                           $self->{cols}, $attrs);
  return (wantarray ? $slice->all : $slice);
}

sub next {
  my ($self) = @_;
  my @row = $self->{cursor}->next;
  return unless (@row);
  return $self->{class}->_row_to_object($self->{cols}, \@row);
}

sub count {
  my ($self) = @_;
  return $self->{attrs}{rows} if $self->{attrs}{rows};
  return $self->{class}->count($self->{cond}, { bind => $self->{args} });
}

sub all {
  my ($self) = @_;
  $self->reset;
  my @all;
  while (my $obj = $self->next) {
    push(@all, $obj);
  }
  $self->reset;
  return @all;
}

sub reset {
  my ($self) = @_;
  $self->{cursor}->reset;
  return $self;
}

sub first {
  return $_[0]->reset->next;
}

sub delete_all {
  my ($self) = @_;
  $_->delete for $self->all;
  return 1;
}

1;
