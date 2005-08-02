package DBIx::Class::Cursor;

use strict;
use warnings;
use overload
        '0+'     => 'count',
        fallback => 1;

sub new {
  my ($it_class, $db_class, $sth, $args, $cols, $attrs) = @_;
  #use Data::Dumper; warn Dumper(@_);
  $it_class = ref $it_class if ref $it_class;
  unless ($sth) {
    $sth = $db_class->_get_sth('select', $cols,
                             $db_class->_table_name, $attrs->{where});
  }
  my $new = {
    class => $db_class,
    sth => $sth,
    cols => $cols,
    args => $args,
    pos => 0,
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
  return if $self->{attrs}{rows}
    && $self->{pos} >= $self->{attrs}{rows}; # + $self->{attrs}{offset});
  unless ($self->{live_sth}) {
    $self->{sth}->execute(@{$self->{args} || []});
    if (my $offset = $self->{attrs}{offset}) {
      $self->{sth}->fetchrow_array for 1 .. $offset;
    }
    $self->{live_sth} = 1;
  }
  my @row = $self->{sth}->fetchrow_array;
  return unless (@row);
  $self->{pos}++;
  return $self->{class}->_row_to_object($self->{cols}, \@row);
}

sub count {
  my ($self) = @_;
  return $self->{attrs}{rows} if $self->{attrs}{rows};
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
  my ($self) = @_;
  $self->{sth}->finish if $self->{sth}->{Active};
  $self->{pos} = 0;
  $self->{live_sth} = 0;
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
