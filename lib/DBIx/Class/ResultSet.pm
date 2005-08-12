package DBIx::Class::ResultSet;

use strict;
use warnings;
use overload
        '0+'     => 'count',
        fallback => 1;

sub new {
  my ($it_class, $db_class, $attrs) = @_;
  #use Data::Dumper; warn Dumper(@_);
  $it_class = ref $it_class if ref $it_class;
  $attrs = { %{ $attrs || {} } };
  my $cols = [ $db_class->_select_columns ];
  my $cursor = $db_class->storage->select($db_class->_table_name,$cols,
                                        $attrs->{where},$attrs);
  my $new = {
    class => $db_class,
    cursor => $cursor,
    cols => $cols,
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
  my $slice = $self->new($self->{class}, $attrs);
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
    # This is a hack, and will break on the last page of a paged set.
    # Once we have limit support in Storage, kill it.

  my $db_class = $self->{class};
  my @cols = 'COUNT(*)';
  my ($c) = $db_class->storage->select_single($db_class->_table_name, \@cols,
                                            $self->{cond}, $self->{attrs});
  return $c; # ($cursor->next)[0];
}

sub all {
  my ($self) = @_;
  return map { $self->{class}->_row_to_object($self->{cols}, $_); }
           $self->{cursor}->all;
}

sub reset {
  my ($self) = @_;
  $self->{cursor}->reset;
  return $self;
}

sub first {
  return $_[0]->reset->next;
}

sub delete {
  my ($self) = @_;
  $_->delete for $self->all;
  return 1;
}

*delete_all = \&delete; # Yeah, yeah, yeah ...

1;
