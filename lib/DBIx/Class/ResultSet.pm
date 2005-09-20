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
  my %seen;
  $attrs->{cols} ||= [ map { "me.$_" } $db_class->_select_columns ];
  $attrs->{from} ||= [ { 'me' => $db_class->_table_name } ];
  if ($attrs->{join}) {
    foreach my $j (ref $attrs->{join} eq 'ARRAY'
              ? (@{$attrs->{join}}) : ($attrs->{join})) {
      if (ref $j eq 'HASH') {
        $seen{$_} = 1 foreach keys %$j;
      } else {
        $seen{$j} = 1;
      }
    }
    push(@{$attrs->{from}}, $db_class->_resolve_join($attrs->{join}, 'me'));
  }
  foreach my $pre (@{$attrs->{prefetch} || []}) {
    push(@{$attrs->{from}}, $db_class->_resolve_join($pre, 'me'))
      unless $seen{$pre};
    push(@{$attrs->{cols}},
      map { "$pre.$_" }
      $db_class->_relationships->{$pre}->{class}->_select_columns);
  }
  my $new = {
    class => $db_class,
    cols => $attrs->{cols} || [ $db_class->_select_columns ],
    cond => $attrs->{where},
    from => $attrs->{from} || $db_class->_table_name,
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
    ||= $db_class->storage->select($self->{from}, $self->{cols},
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
  return $self->_construct_object(@row);
}

sub _construct_object {
  my ($self, @row) = @_;
  my @cols = $self->{class}->_select_columns;
  my $new;
  unless ($self->{attrs}{prefetch}) {
    $new = $self->{class}->_row_to_object(\@cols, \@row);
  } else {
    my @main = splice(@row, 0, scalar @cols);
    $new = $self->{class}->_row_to_object(\@cols, \@main);
    PRE: foreach my $pre (@{$self->{attrs}{prefetch}}) {
      my $rel_obj = $self->{class}->_relationships->{$pre};
      my @pre_cols = $rel_obj->{class}->columns;
      my @vals = splice(@row, 0, scalar @pre_cols);
      my $fetched = $rel_obj->{class}->_row_to_object(\@pre_cols, \@vals);
      $self->{class}->throw("No accessor for prefetched $pre")
        unless defined $rel_obj->{attrs}{accessor};
      if ($rel_obj->{attrs}{accessor} eq 'single') {
        foreach my $pri ($rel_obj->{class}->primary_columns) {
          next PRE unless defined $fetched->get_column($pri);
        }
        $new->{_relationship_data}{$pre} = $fetched;
      } elsif ($rel_obj->{attrs}{accessor} eq 'filter') {
        $new->{_inflated_column}{$pre} = $fetched;
      } else {
        $self->{class}->throw("Don't know to to store prefetched $pre");
      }
    }
  }
  $new = $self->{attrs}{record_filter}->($new)
    if exists $self->{attrs}{record_filter};
  return $new;
}

sub count {
  my ($self) = @_;
  my $db_class = $self->{class};
  my $attrs = { %{ $self->{attrs} } };
  unless ($self->{count}) {
    # offset and order by are not needed to count
    delete $attrs->{$_} for qw/offset order_by/;
        
    my @cols = 'COUNT(*)';
    $self->{count} = $db_class->storage->select_single($self->{from}, \@cols,
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
  return map { $self->_construct_object(@$_); }
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
