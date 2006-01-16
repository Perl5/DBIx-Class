package DBIx::Class::ResultSet;

use strict;
use warnings;
use overload
        '0+'     => 'count',
        fallback => 1;
use Data::Page;
use Storable;

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
  my $class = shift;
  return $class->new_result(@_) if ref $class;
  my ($source, $attrs) = @_;
  #use Data::Dumper; warn Dumper($attrs);
  $attrs = Storable::dclone($attrs || {}); # { %{ $attrs || {} } };
  my %seen;
  my $alias = ($attrs->{alias} ||= 'me');
  if (!$attrs->{select}) {
    my @cols = ($attrs->{cols}
                 ? @{delete $attrs->{cols}}
                 : $source->result_class->_select_columns);
    $attrs->{select} = [ map { m/\./ ? $_ : "${alias}.$_" } @cols ];
  }
  $attrs->{as} ||= [ map { m/^$alias\.(.*)$/ ? $1 : $_ } @{$attrs->{select}} ];
  #use Data::Dumper; warn Dumper(@{$attrs}{qw/select as/});
  $attrs->{from} ||= [ { $alias => $source->from } ];
  if (my $join = delete $attrs->{join}) {
    foreach my $j (ref $join eq 'ARRAY'
              ? (@{$join}) : ($join)) {
      if (ref $j eq 'HASH') {
        $seen{$_} = 1 foreach keys %$j;
      } else {
        $seen{$j} = 1;
      }
    }
    push(@{$attrs->{from}}, $source->resolve_join($join, $attrs->{alias}));
  }
  $attrs->{group_by} ||= $attrs->{select} if delete $attrs->{distinct};
  foreach my $pre (@{delete $attrs->{prefetch} || []}) {
    push(@{$attrs->{from}}, $source->resolve_join($pre, $attrs->{alias}))
      unless $seen{$pre};
    my @pre = 
      map { "$pre.$_" }
      $source->related_source($pre)->columns;
    push(@{$attrs->{select}}, @pre);
    push(@{$attrs->{as}}, @pre);
  }
  if ($attrs->{page}) {
    $attrs->{rows} ||= 10;
    $attrs->{offset} ||= 0;
    $attrs->{offset} += ($attrs->{rows} * ($attrs->{page} - 1));
  }
  my $new = {
    source => $source,
    cond => $attrs->{where},
    from => $attrs->{from},
    count => undef,
    page => delete $attrs->{page},
    pager => undef,
    attrs => $attrs };
  bless ($new, $class);
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
    $attrs = { %$attrs, %{ pop(@_) } };
  }

  my $where = (@_ ? ((@_ == 1 || ref $_[0] eq "HASH") ? shift : {@_}) : undef());
  if (defined $where) {
    $where = (defined $attrs->{where}
                ? { '-and' =>
                    [ map { ref $_ eq 'ARRAY' ? [ -or => $_ ] : $_ }
                        $where, $attrs->{where} ] }
                : $where);
    $attrs->{where} = $where;
  }

  my $rs = (ref $self)->new($self->{source}, $attrs);

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

=head2 find(@colvalues), find(\%cols)

Finds a row based on its primary key(s).                                        

=cut                                                                            

sub find {
  my ($self, @vals) = @_;
  my $attrs = (@vals > 1 && ref $vals[$#vals] eq 'HASH' ? pop(@vals) : {});
  my @pk = $self->{source}->primary_columns;
  #use Data::Dumper; warn Dumper($attrs, @vals, @pk);
  $self->{source}->result_class->throw( "Can't find unless primary columns are defined" )
    unless @pk;
  my $query;
  if (ref $vals[0] eq 'HASH') {
    $query = $vals[0];
  } elsif (@pk == @vals) {
    $query = {};
    @{$query}{@pk} = @vals;
  } else {
    $query = {@vals};
  }
  #warn Dumper($query);
  # Useless -> disabled
  #$self->{source}->result_class->throw( "Can't find unless all primary keys are specified" )
  #  unless (keys %$query >= @pk); # If we check 'em we run afoul of uc/lc
                                  # column names etc. Not sure what to do yet
  return $self->search($query)->next;
}

=head2 search_related

  $rs->search_related('relname', $cond?, $attrs?);

=cut

sub search_related {
  my ($self, $rel, @rest) = @_;
  my $rel_obj = $self->{source}->relationship_info($rel);
  $self->{source}->result_class->throw(
    "No such relationship ${rel} in search_related")
      unless $rel_obj;
  my $rs = $self->search(undef, { join => $rel });
  return $self->{source}->schema->resultset($rel_obj->{class}
           )->search( undef,
             { %{$rs->{attrs}},
               alias => $rel,
               select => undef(),
               as => undef() }
           )->search(@rest);
}

=head2 cursor

Returns a storage-driven cursor to the given resultset.

=cut

sub cursor {
  my ($self) = @_;
  my ($source, $attrs) = @{$self}{qw/source attrs/};
  $attrs = { %$attrs };
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
  $attrs->{offset} ||= 0;
  $attrs->{offset} += $min;
  $attrs->{rows} = ($max ? ($max - $min + 1) : 1);
  my $slice = (ref $self)->new($self->{source}, $attrs);
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
  my (%me, %pre);
  foreach my $col (@cols) {
    if ($col =~ /([^\.]+)\.([^\.]+)/) {
      $pre{$1}[0]{$2} = shift @row;
    } else {
      $me{$col} = shift @row;
    }
  }
  my $new = $self->{source}->result_class->inflate_result(
              $self->{source}, \%me, \%pre);
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
  die "Unable to ->count with a GROUP BY" if defined $self->{attrs}{group_by};
  unless (defined $self->{count}) {
    my $attrs = { %{ $self->{attrs} },
                  select => { 'count' => '*' },
                  as => [ 'count' ] };
    # offset, order by and page are not needed to count. record_filter is cdbi
    delete $attrs->{$_} for qw/rows offset order_by page pager record_filter/;
        
    ($self->{count}) = (ref $self)->new($self->{source}, $attrs)->cursor->next;
  }
  return 0 unless $self->{count};
  my $count = $self->{count};
  $count -= $self->{attrs}{offset} if $self->{attrs}{offset};
  $count = $self->{attrs}{rows} if
    ($self->{attrs}{rows} && $self->{attrs}{rows} < $count);
  return $count;
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

=head2 update(\%values)

Sets the specified columns in the resultset to the supplied values

=cut

sub update {
  my ($self, $values) = @_;
  die "Values for update must be a hash" unless ref $values eq 'HASH';
  return $self->{source}->storage->update(
           $self->{source}->from, $values, $self->{cond});
}

=head2 update_all(\%values)

Fetches all objects and updates them one at a time. ->update_all will run
cascade triggers, ->update will not.

=cut

sub update_all {
  my ($self, $values) = @_;
  die "Values for update must be a hash" unless ref $values eq 'HASH';
  foreach my $obj ($self->all) {
    $obj->set_columns($values)->update;
  }
  return 1;
}

=head2 delete

Deletes the contents of the resultset from its result source.

=cut

sub delete {
  my ($self) = @_;
  $self->{source}->storage->delete($self->{source}->from, $self->{cond});
  return 1;
}

=head2 delete_all

Fetches all objects and deletes them one at a time. ->delete_all will run
cascade triggers, ->delete will not.

=cut

sub delete_all {
  my ($self) = @_;
  $_->delete for $self->all;
  return 1;
}

=head2 pager

Returns a L<Data::Page> object for the current resultset. Only makes
sense for queries with page turned on.

=cut

sub pager {
  my ($self) = @_;
  my $attrs = $self->{attrs};
  die "Can't create pager for non-paged rs" unless $self->{page};
  $attrs->{rows} ||= 10;
  $self->count;
  return $self->{pager} ||= Data::Page->new(
    $self->{count}, $attrs->{rows}, $self->{page});
}

=head2 page($page_num)

Returns a new resultset for the specified page.

=cut

sub page {
  my ($self, $page) = @_;
  my $attrs = { %{$self->{attrs}} };
  $attrs->{page} = $page;
  return (ref $self)->new($self->{source}, $attrs);
}

=head2 new_result(\%vals)

Creates a result in the resultset's result class

=cut

sub new_result {
  my ($self, $values) = @_;
  $self->{source}->result_class->throw( "new_result needs a hash" )
    unless (ref $values eq 'HASH');
  $self->{source}->result_class->throw( "Can't abstract implicit construct, condition not a hash" )
    if ($self->{cond} && !(ref $self->{cond} eq 'HASH'));
  my %new = %$values;
  my $alias = $self->{attrs}{alias};
  foreach my $key (keys %{$self->{cond}||{}}) {
    $new{$1} = $self->{cond}{$key} if ($key =~ m/^(?:$alias\.)?([^\.]+)$/);
  }
  return $self->{source}->result_class->new(\%new);
}

=head2 create(\%vals)

Inserts a record into the resultset and returns the object

Effectively a shortcut for ->new_result(\%vals)->insert

=cut

sub create {
  my ($self, $attrs) = @_;
  $self->{source}->result_class->throw( "create needs a hashref" ) unless ref $attrs eq 'HASH';
  return $self->new_result($attrs)->insert;
}

=head2 find_or_create(\%vals)

  $class->find_or_create({ key => $val, ... });                                 
                                                                                
Searches for a record matching the search condition; if it doesn't find one,    
creates one and returns that instead.                                           
                                                                                
=cut

sub find_or_create {
  my $self     = shift;
  my $hash     = ref $_[0] eq "HASH" ? shift: {@_};
  my $exists   = $self->find($hash);
  return defined($exists) ? $exists : $self->create($hash);
}

=head1 ATTRIBUTES

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

=head2 group_by

A list of columns to group by (note that 'count' doesn't work on grouped
resultsets)

=head2 distinct

Set to 1 to group by all columns

=cut

1;
