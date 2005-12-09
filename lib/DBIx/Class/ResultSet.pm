package DBIx::Class::ResultSet;

use strict;
use warnings;
use overload
        '0+'     => 'count',
        fallback => 1;
use Data::Page;

=head1 NAME

DBIx::Class::ResultSet - Responsible for fetching and creating resultset.

=head1 SYNOPSIS;

$rs=MyApp::DB::Class->search(registered=>1);

=head1 DESCRIPTION

The resultset is also known as an iterator.

=head1 METHODS

=over 4

=item new  <db_class> <attrs>

The resultset constructor. Takes a db class and an
attribute hash (see below for more info on attributes)

=cut

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

=item cursor

Return a storage driven cursor to the given resultset.

=cut

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

=item slice <first> <last>

return a number of elements from the given resultset.

=cut

sub slice {
  my ($self, $min, $max) = @_;
  my $attrs = { %{ $self->{attrs} || {} } };
  $self->{class}->throw("Can't slice without where") unless $attrs->{where};
  $attrs->{offset} = $min;
  $attrs->{rows} = ($max ? ($max - $min + 1) : 1);
  my $slice = $self->new($self->{class}, $attrs);
  return (wantarray ? $slice->all : $slice);
}

=item next 

Returns the next element in this resultset.

=cut

sub next {
  my ($self) = @_;
  my @row = $self->cursor->next;
  return unless (@row);
  return $self->_construct_object(@row);
}

sub _construct_object {
  my ($self, @row) = @_;
  my @cols = @{ $self->{attrs}{cols} };
  s/^me\.// for @cols;
  @cols = grep { /\(/ or ! /\./ } @cols;
  my $new;
  unless ($self->{attrs}{prefetch}) {
    $new = $self->{class}->_row_to_object(\@cols, \@row);
  } else {
    my @main = splice(@row, 0, scalar @cols);
    $new = $self->{class}->_row_to_object(\@cols, \@main);
    PRE: foreach my $pre (@{$self->{attrs}{prefetch}}) {
      my $rel_obj = $self->{class}->_relationships->{$pre};
      my $pre_class = $self->{class}->resolve_class($rel_obj->{class});
      my @pre_cols = $pre_class->_select_columns;
      my @vals = splice(@row, 0, scalar @pre_cols);
      my $fetched = $pre_class->_row_to_object(\@pre_cols, \@vals);
      $self->{class}->throw("No accessor for prefetched $pre")
        unless defined $rel_obj->{attrs}{accessor};
      if ($rel_obj->{attrs}{accessor} eq 'single') {
        foreach my $pri ($rel_obj->{class}->primary_columns) {
          unless (defined $fetched->get_column($pri)) {
            undef $fetched;
            last;
          }
        }
        $new->{_relationship_data}{$pre} = $fetched;
      } elsif ($rel_obj->{attrs}{accessor} eq 'filter') {
        $new->{_inflated_column}{$pre} = $fetched;
      } else {
        $self->{class}->throw("Don't know how to store prefetched $pre");
      }
    }
  }
  $new = $self->{attrs}{record_filter}->($new)
    if exists $self->{attrs}{record_filter};
  return $new;
}

=item count

Performs an SQL count with the same query as the resultset was built
with to find the number of elements.

=cut


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

=item all

Returns all elements in the resultset. Is called implictly if the search
method is used in list context.

=cut

sub all {
  my ($self) = @_;
  return map { $self->_construct_object(@$_); }
           $self->cursor->all;
}

=item reset

Reset this resultset's cursor, so you can iterate through the elements again.

=cut

sub reset {
  my ($self) = @_;
  $self->cursor->reset;
  return $self;
}

=item first

resets the resultset and returns the first element.

=cut

sub first {
  return $_[0]->reset->next;
}

=item delete

Deletes all elements in the resultset.

=cut

sub delete {
  my ($self) = @_;
  $_->delete for $self->all;
  return 1;
}

*delete_all = \&delete; # Yeah, yeah, yeah ...

=item pager

Returns a L<Data::Page> object for the current resultset. Only makes
sense for queries with page turned on.

=cut

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

=item page <page>

Returns a new resultset representing a given page.

=cut

sub page {
  my ($self, $page) = @_;
  my $attrs = $self->{attrs};
  $attrs->{page} = $page;
  return $self->new($self->{class}, $attrs);
}

=back 

=head1 Attributes

The resultset is responsible for handling the various attributes that
can be passed in with the search functions. Here's an overview of them:

=over 4

=item order_by

Which column to order the results by. 

=item cols

Which cols should be retrieved on the first search.

=item join

Contains a list of relations that should be joined for this query. Can also 
contain a hash referece to refer to that relation's relations.

=item from 

This attribute can contain a arrayref of  elements. each element can be another
arrayref, to nest joins, or it can be a hash which represents the two sides
of the join. 

*NOTE* Use this on your own risk. This allows you to shoot your foot off!

=item page

Should the resultset be paged? This can also be enabled by using the 
'page' option.

=item rows

For paged resultsset, how  many rows per page

=item  offset

For paged resultsset, which page to start on.

=back

1;
