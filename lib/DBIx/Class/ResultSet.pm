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

=head2 new($source, \%$attrs)

The resultset constructor. Takes a source object (usually a DBIx::Class::Table)
and an attribute hash (see below for more information on attributes). Does
not perform any queries -- these are executed as needed by the other methods.

=cut

sub new {
  my ($class, $source, $attrs) = @_;
  #use Data::Dumper; warn Dumper(@_);
  $class = ref $class if ref $class;
  $attrs = { %{ $attrs || {} } };
  my %seen;
  if (!$attrs->{select}) {
    my @cols = ($attrs->{cols}
                 ? @{delete $attrs->{cols}}
                 : $source->result_class->_select_columns);
    $attrs->{select} = [ map { m/\./ ? $_ : "me.$_" } @cols ];
  }
  $attrs->{as} ||= [ map { m/^me\.(.*)$/ ? $1 : $_ } @{$attrs->{select}} ];
  #use Data::Dumper; warn Dumper(@{$attrs}{qw/select as/});
  $attrs->{from} ||= [ { 'me' => $source->name } ];
  if ($attrs->{join}) {
    foreach my $j (ref $attrs->{join} eq 'ARRAY'
              ? (@{$attrs->{join}}) : ($attrs->{join})) {
      if (ref $j eq 'HASH') {
        $seen{$_} = 1 foreach keys %$j;
      } else {
        $seen{$j} = 1;
      }
    }
    push(@{$attrs->{from}}, $source->result_class->_resolve_join($attrs->{join}, 'me'));
  }
  foreach my $pre (@{$attrs->{prefetch} || []}) {
    push(@{$attrs->{from}}, $source->result_class->_resolve_join($pre, 'me'))
      unless $seen{$pre};
    my @pre = 
      map { "$pre.$_" }
      $source->result_class->_relationships->{$pre}->{class}->columns;
    push(@{$attrs->{select}}, @pre);
    push(@{$attrs->{as}}, @pre);
  }
  my $new = {
    source => $source,
    cond => $attrs->{where},
    from => $attrs->{from},
    count => undef,
    pager => undef,
    attrs => $attrs };
  bless ($new, $class);
  $new->pager if $attrs->{page};
  return $new;
}

=head2 search

  my @obj    = $rs->search({ foo => 3 }); # "... WHERE foo = 3"              
  my $new_rs = $rs->search({ foo => 3 });                                    
                                                                                
If you need to pass in additional attributes but no additional condition,
call it as ->search(undef, \%attrs);
                                                                                
  my @all = $class->search({}, { cols => [qw/foo bar/] }); # "SELECT foo, bar FROM $class_table"

=cut

sub search {
  my $self = shift;

  #use Data::Dumper;warn Dumper(@_);

  my $attrs = { %{$self->{attrs}} };
  if (@_ > 1 && ref $_[$#_] eq 'HASH') {
    $attrs = { %{ pop(@_) } };
  }

  my $where = ((@_ == 1 || ref $_[0] eq "HASH") ? shift : {@_});
  if (defined $where) {
    $where = (defined $attrs->{where}
                ? { '-and' => [ $where, $attrs->{where} ] }
                : $where);
    $attrs->{where} = $where;
  }

  my $rs = $self->new($self->{source}, $attrs);

  return (wantarray ? $rs->all : $rs);
}

=head2 search_literal                                                              
  my @obj    = $rs->search_literal($literal_where_cond, @bind);
  my $new_rs = $rs->search_literal($literal_where_cond, @bind);

Pass a literal chunk of SQL to be added to the conditional part of the
resultset

=cut
                                                         
sub search_literal {
  my ($self, $cond, @vals) = @_;
  my $attrs = (ref $vals[$#vals] eq 'HASH' ? { %{ pop(@vals) } } : {});
  $attrs->{bind} = [ @{$self->{attrs}{bind}||[]}, @vals ];
  return $self->search(\$cond, $attrs);
}

=head2 cursor

Returns a storage-driven cursor to the given resultset.

=cut

sub cursor {
  my ($self) = @_;
  my ($source, $attrs) = @{$self}{qw/source attrs/};
  if ($attrs->{page}) {
    $attrs->{rows} = $self->pager->entries_per_page;
    $attrs->{offset} = $self->pager->skipped;
  }
  return $self->{cursor}
    ||= $source->storage->select($self->{from}, $attrs->{select},
          $attrs->{where},$attrs);
}

=head2 search_like                                                               
                                                                                
Identical to search except defaults to 'LIKE' instead of '=' in condition       
                                                                                
=cut                                                                            

sub search_like {
  my $class    = shift;
  my $attrs = { };
  if (@_ > 1 && ref $_[$#_] eq 'HASH') {
    $attrs = pop(@_);
  }
  my $query    = ref $_[0] eq "HASH" ? { %{shift()} }: {@_};
  $query->{$_} = { 'like' => $query->{$_} } for keys %$query;
  return $class->search($query, { %$attrs });
}

=head2 slice($first, $last)

Returns a subset of elements from the resultset.

=cut

sub slice {
  my ($self, $min, $max) = @_;
  my $attrs = { %{ $self->{attrs} || {} } };
  $self->{source}->result_class->throw("Can't slice without where") unless $attrs->{where};
  $attrs->{offset} = $min;
  $attrs->{rows} = ($max ? ($max - $min + 1) : 1);
  my $slice = $self->new($self->{source}, $attrs);
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
  my @cols = @{ $self->{attrs}{as} };
  #warn "@cols -> @row";
  @cols = grep { /\(/ or ! /\./ } @cols;
  my $new;
  unless ($self->{attrs}{prefetch}) {
    $new = $self->{source}->result_class->_row_to_object(\@cols, \@row);
  } else {
    my @main = splice(@row, 0, scalar @cols);
    $new = $self->{source}->result_class->_row_to_object(\@cols, \@main);
    PRE: foreach my $pre (@{$self->{attrs}{prefetch}}) {
      my $rel_obj = $self->{source}->result_class->_relationships->{$pre};
      my $pre_class = $self->{source}->result_class->resolve_class($rel_obj->{class});
      my @pre_cols = $pre_class->_select_columns;
      my @vals = splice(@row, 0, scalar @pre_cols);
      my $fetched = $pre_class->_row_to_object(\@pre_cols, \@vals);
      $self->{source}->result_class->throw("No accessor for prefetched $pre")
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
        $self->{source}->result_class->throw("Don't know how to store prefetched $pre");
      }
    }
  }
  $new = $self->{attrs}{record_filter}->($new)
    if exists $self->{attrs}{record_filter};
  return $new;
}

=head2 count

Performs an SQL C<COUNT> with the same query as the resultset was built
with to find the number of elements. If passed arguments, does a search
on the resultset and counts the results of that.

=cut

sub count {
  my $self = shift;
  return $self->search(@_)->count if @_ && defined $_[0];
  unless ($self->{count}) {
    my $attrs = { %{ $self->{attrs} },
                  select => [ 'COUNT(*)' ], as => [ 'count' ] };
    # offset and order by are not needed to count, page, join and prefetch
    # will get in the way (add themselves to from again ...)
    delete $attrs->{$_} for qw/offset order_by page join prefetch/;
        
    my @cols = 'COUNT(*)';
    ($self->{count}) = $self->search(undef, $attrs)->cursor->next;
  }
  return 0 unless $self->{count};
  return $self->{pager}->entries_on_this_page if ($self->{pager});
  return ( $self->{attrs}->{rows} && $self->{attrs}->{rows} < $self->{count} ) 
    ? $self->{attrs}->{rows} 
    : $self->{count};
}

=head2 count_literal

Calls search_literal with the passed arguments, then count.

=cut

sub count_literal { shift->search_literal(@_)->count; }

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
  return $self->new($self->{source}, $attrs);
}

=head1 Attributes

The resultset takes various attributes that modify its behavior.
Here's an overview of them:

=head2 order_by

Which column(s) to order the results by. This is currently passed
through directly to SQL, so you can give e.g. C<foo DESC> for a 
descending order.

=head2 cols (arrayref)

Shortcut to request a particular set of columns to be retrieved - adds
'me.' onto the start of any column without a '.' in it and sets 'select'
from that, then auto-populates 'as' from 'select' as normal

=head2 select (arrayref)

Indicates which columns should be selected from the storage

=head2 as (arrayref)

Indicates column names for object inflation

=head2 join

Contains a list of relationships that should be joined for this query. Can also 
contain a hash reference to refer to that relation's relations. So, if one column
in your class C<belongs_to> foo and another C<belongs_to> bar, you can do
C<< join => [qw/ foo bar /] >> to join both (and e.g. use them for C<order_by>).
If a foo contains many margles and you want to join those too, you can do
C<< join => { foo => 'margle' } >>. If you want to fetch the columns from the
related table as well, see C<prefetch> below.

=head2 prefetch

Contains a list of relationships that should be fetched along with the main 
query (when they are accessed afterwards they will have already been
"prefetched"). This is useful for when you know you will need the related
object(s), because it saves a query. Currently limited to prefetching
one relationship deep, so unlike C<join>, prefetch must be an arrayref.

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
