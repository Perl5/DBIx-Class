package DBIx::Class::ResultSet;

use strict;
use warnings;
use overload
        '0+'     => 'count',
        fallback => 1;
use Data::Page;

sub new {
  my ($it_class, $db_class, $attrs) = @_;
  #use Data::Dumper; warn Dumper(@_);
  $it_class = ref $it_class if ref $it_class;
  $attrs = { %{ $attrs || {} } };
  my $cols = [ $db_class->_select_columns ];
  my $new = {
    class => $db_class,
    cols => $cols,
    cond => $attrs->{where},
    count => undef,
    pager => undef,
    attrs => $attrs };
  bless ($new, $it_class);
  $new->pager if ($attrs->{page});
  return $new;
}

sub cursor {
  my ($self) = @_;
  my ($db_class, $attrs) = @{$self}{qw/class attrs/};
  if ($attrs->{page}) {
    $attrs->{rows} = $self->pager->entries_per_page;
    $attrs->{offset} = $self->pager->skipped;
  }
  return $self->{cursor}
    ||= $db_class->storage->select($db_class->_table_name, $self->{cols},
          $attrs->{where},$attrs);
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
  my @row = $self->cursor->next;
  return unless (@row);
  return $self->{class}->_row_to_object($self->{cols}, \@row);
}

sub count {
  my ($self) = @_;
  my $db_class = $self->{class};
  my $attrs = { %{ $self->{attrs} } };
  unless ($self->{count}) {
    # offset and order by are not needed to count
    delete $attrs->{$_} for qw/offset order_by/;
        
    my @cols = 'COUNT(*)';
    $self->{count} = $db_class->storage->select_single($db_class->_table_name, \@cols,
                                              $self->{cond}, $attrs);
  }
  return 0 unless $self->{count};
  return $self->{pager}->entries_on_this_page if ($self->{pager});
  return ( $attrs->{rows} && $attrs->{rows} < $self->{count} ) 
    ? $attrs->{rows} 
    : $self->{count};
}

sub all {
  my ($self) = @_;
  return map { $self->{class}->_row_to_object($self->{cols}, $_); }
           $self->cursor->all;
}

sub reset {
  my ($self) = @_;
  $self->cursor->reset;
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

sub pager {
  my ($self) = @_;
  my $attrs = $self->{attrs};
  delete $attrs->{offset};
  my $rows_per_page = delete $attrs->{rows} || 10;
  $self->{pager} ||= Data::Page->new(
    $self->count, $rows_per_page, $attrs->{page} || 1);
  $attrs->{rows} = $rows_per_page;
  return $self->{pager};
}

sub page {
  my ($self, $page) = @_;
  my $attrs = $self->{attrs};
  $attrs->{page} = $page;
  return $self->new($self->{class}, $attrs);
}

1;
