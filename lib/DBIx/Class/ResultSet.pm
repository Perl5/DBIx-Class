package DBIx::Class::ResultSet;

use strict;
use warnings;
use overload
        '0+'     => 'count',
        fallback => 1;
use Data::Page;

=head1 NAME

DBIx::Class::ResultSet - Responsible for fetching and creating resultset.

=head1 SYNOPSIS

my $rs = MyApp::DB::Class->search(registered => 1);
my @rows = MyApp::DB::Class->search(foo => 'bar');

=head1 DESCRIPTION

The resultset is also known as an iterator. It is responsible for handling
queries that may return an arbitrary number of rows, e.g. via C<search>
or a C<has_many> relationship.

=head1 METHODS

=head2 new($db_class, \%$attrs)

The resultset constructor. Takes a table class and an attribute hash
(see below for more information on attributes). Does not perform
any queries -- these are executed as needed by the other methods.

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

=head2 cursor

Return a storage-driven cursor to the given resultset.

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

=head2 slice($first, $last)

Returns a subset of elements from the resultset.

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

=head2 next 

Returns the next element in the resultset (undef is there is none).

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

=head2 count

Performs an SQL C<COUNT> with the same query as the resultset was built
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

=head2 all

Returns all elements in the resultset. Called implictly if the resultset
is returned in list context.

=cut

sub all {
  my ($self) = @_;
  return map { $self->_construct_object(@$_); }
           $self->cursor->all;
}

=head2 reset

Resets the resultset's cursor, so you can iterate through the elements again.

=cut

sub reset {
  my ($self) = @_;
  $self->cursor->reset;
  return $self;
}

=head2 first

Resets the resultset and returns the first element.

=cut

sub first {
  return $_[0]->reset->next;
}

=head2 delete

Deletes all elements in the resultset.

=cut

sub delete {
  my ($self) = @_;
  $_->delete for $self->all;
  return 1;
}

*delete_all = \&delete; # Yeah, yeah, yeah ...

=head2 pager

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

=head2 page($page_num)

Returns a new resultset for the specified page.

=cut

sub page {
  my ($self, $page) = @_;
  my $attrs = $self->{attrs};
  $attrs->{page} = $page;
  return $self->new($self->{class}, $attrs);
}

=head1 Attributes

The resultset takes various attributes that modify its behavior.
Here's an overview of them:

=head2 order_by

Which column(s) to order the results by. This is currently passed
through directly to SQL, so you can give e.g. C<foo DESC> for a 
descending order.

=head2 cols

Which columns should be retrieved.

=head2 join

Contains a list of relations that should be joined for this query. Can also 
contain a hash reference to refer to that relation's relations. So, if one column
in your class C<belongs_to> foo and another C<belongs_to> bar, you can do
C<< join => [qw/ foo bar /] >> to join both (and e.g. use them for C<order_by>).
If a foo contains many margles and you want to join those too, you can do
C<< join => { foo => 'margle' } >>. If you want to fetch the columns from the
related table as well, see C<prefetch> below.

=head2 from 

This attribute can contain a arrayref of elements. Each element can be another
arrayref, to nest joins, or it can be a hash which represents the two sides
of the join. 

NOTE: Use this on your own risk. This allows you to shoot your foot off!

=head2 page

For a paged resultset, specifies which page to retrieve. Leave unset
for an unpaged resultset.

=head2 rows

For a paged resultset, how many rows per page

=cut

1;
