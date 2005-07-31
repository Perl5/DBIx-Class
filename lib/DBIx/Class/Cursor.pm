package DBIx::Class::Cursor;

use strict;
use warnings;
use overload
        '0+'     => 'count',
        fallback => 1;

sub new {
  my ($it_class, $db_class, $sth, $args, $cols, $attrs) = @_;
  $sth->execute(@{$args || []}) unless $sth->{Active};
  my $new = {
    class => $db_class,
    sth => $sth,
    cols => $cols,
    args => $args,
    attrs => $attrs };
  return bless ($new, $it_class);
}

sub next {
  my ($self) = @_;
  my @row = $self->{sth}->fetchrow_array;
  return unless @row;
  #unless (@row) { $self->{sth}->finish; return; }
  return $self->{class}->_row_to_object($self->{cols}, \@row);
}

sub count {
  my ($self) = @_;
  if (my $cond = $self->{attrs}->{where}) {
    my $class = $self->{class};
    my $sth = $class->_get_sth( 'select', [ 'COUNT(*)' ],
                                  $class->_table_name, $cond);
    my ($count) = $class->_get_dbh->selectrow_array(
                                      $sth, undef, @{$self->{args} || []});
    return $count;
  } else {
    return scalar $_[0]->all; # So inefficient
  }
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
  $_[0]->{sth}->finish if $_[0]->{sth}->{Active};
  $_[0]->{sth}->execute(@{$_[0]->{args} || []});
  return $_[0];
}

sub first {
  return $_[0]->reset->next;
}

1;
