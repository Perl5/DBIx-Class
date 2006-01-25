package DBIx::Class::ResultSet;

use strict;
use warnings;
use Carp qw/croak/;
use overload
        '0+'     => 'count',
        'bool'   => sub { 1; },
        fallback => 1;
use Data::Page;
use Storable;

=head1 NAME

DBIx::Class::ResultSet - Responsible for fetching and creating resultset.

=head1 SYNOPSIS

  my $rs   = $schema->resultset('User')->search(registered => 1);
  my @rows = $schema->resultset('Foo')->search(bar => 'baz');

=head1 DESCRIPTION

The resultset is also known as an iterator. It is responsible for handling
queries that may return an arbitrary number of rows, e.g. via L</search>
or a C<has_many> relationship.

In the examples below, the following table classes are used:

  package MyApp::Schema::Artist;
  use base qw/DBIx::Class/;
  __PACKAGE__->table('artist');
  __PACKAGE__->add_columns(qw/artistid name/);
  __PACKAGE__->set_primary_key('artistid');
  __PACKAGE__->has_many(cds => 'MyApp::Schema::CD');
  1;

  package MyApp::Schema::CD;
  use base qw/DBIx::Class/;
  __PACKAGE__->table('artist');
  __PACKAGE__->add_columns(qw/cdid artist title year/);
  __PACKAGE__->set_primary_key('cdid');
  __PACKAGE__->belongs_to(artist => 'MyApp::Schema::Artist');
  1;

=head1 METHODS

=head2 new($source, \%$attrs)

The resultset constructor. Takes a source object (usually a
L<DBIx::Class::ResultSourceProxy::Table>) and an attribute hash (see L</ATRRIBUTES>
below).  Does not perform any queries -- these are executed as needed by the
other methods.

Generally you won't need to construct a resultset manually.  You'll
automatically get one from e.g. a L</search> called in scalar context:

  my $rs = $schema->resultset('CD')->search({ title => '100th Window' });

=cut

sub new {
  my $class = shift;
  return $class->new_result(@_) if ref $class;
  my ($source, $attrs) = @_;
  #use Data::Dumper; warn Dumper($attrs);
  $attrs = Storable::dclone($attrs || {}); # { %{ $attrs || {} } };
  my %seen;
  my $alias = ($attrs->{alias} ||= 'me');
  if ($attrs->{cols} || !$attrs->{select}) {
    delete $attrs->{as} if $attrs->{cols};
    my @cols = ($attrs->{cols}
                 ? @{delete $attrs->{cols}}
                 : $source->columns);
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
call it as C<search({}, \%attrs);>.

  # "SELECT foo, bar FROM $class_table"
  my @all = $class->search({}, { cols => [qw/foo bar/] });

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
resultset.

=cut
                                                         
sub search_literal {
  my ($self, $cond, @vals) = @_;
  my $attrs = (ref $vals[$#vals] eq 'HASH' ? { %{ pop(@vals) } } : {});
  $attrs->{bind} = [ @{$self->{attrs}{bind}||[]}, @vals ];
  return $self->search(\$cond, $attrs);
}

=head2 find(@colvalues), find(\%cols, \%attrs?)

Finds a row based on its primary key or unique constraint. For example:

  my $cd = $schema->resultset('CD')->find(5);

Also takes an optional C<key> attribute, to search by a specific key or unique
constraint. For example:

  my $cd = $schema->resultset('CD')->find_or_create(
    {
      artist => 'Massive Attack',
      title  => 'Mezzanine',
    },
    { key => 'artist_title' }
  );

See also L</find_or_create> and L</update_or_create>.

=cut

sub find {
  my ($self, @vals) = @_;
  my $attrs = (@vals > 1 && ref $vals[$#vals] eq 'HASH' ? pop(@vals) : {});

  my @cols = $self->{source}->primary_columns;
  if (exists $attrs->{key}) {
    my %uniq = $self->{source}->unique_constraints;
    $self->( "Unknown key " . $attrs->{key} . " on " . $self->name )
      unless exists $uniq{$attrs->{key}};
    @cols = @{ $uniq{$attrs->{key}} };
  }
  #use Data::Dumper; warn Dumper($attrs, @vals, @cols);
  $self->{source}->result_class->throw( "Can't find unless a primary key or unique constraint is defined" )
    unless @cols;

  my $query;
  if (ref $vals[0] eq 'HASH') {
    $query = $vals[0];
  } elsif (@cols == @vals) {
    $query = {};
    @{$query}{@cols} = @vals;
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

Search the specified relationship. Optionally specify a condition for matching
records.

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

Perform a search, but use C<LIKE> instead of equality as the condition. Note
that this is simply a convenience method; you most likely want to use
L</search> with specific operators.

For more information, see L<DBIx::Class::Manual::Cookbook>.

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

Returns the next element in the resultset (C<undef> is there is none).

Can be used to efficiently iterate over records in the resultset:

  my $rs = $schema->resultset('CD')->search({});
  while (my $cd = $rs->next) {
    print $cd->title;
  }

=cut

sub next {
  my ($self) = @_;
  my @row = $self->cursor->next;
#  warn Dumper(\@row); use Data::Dumper;
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
  croak "Unable to ->count with a GROUP BY" if defined $self->{attrs}{group_by};
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

Calls L</search_literal> with the passed arguments, then L</count>.

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

Sets the specified columns in the resultset to the supplied values.

=cut

sub update {
  my ($self, $values) = @_;
  croak "Values for update must be a hash" unless ref $values eq 'HASH';
  return $self->{source}->storage->update(
           $self->{source}->from, $values, $self->{cond});
}

=head2 update_all(\%values)

Fetches all objects and updates them one at a time.  Note that C<update_all>
will run cascade triggers while L</update> will not.

=cut

sub update_all {
  my ($self, $values) = @_;
  croak "Values for update must be a hash" unless ref $values eq 'HASH';
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

Fetches all objects and deletes them one at a time.  Note that C<delete_all>
will run cascade triggers while L</delete> will not.

=cut

sub delete_all {
  my ($self) = @_;
  $_->delete for $self->all;
  return 1;
}

=head2 pager

Returns a L<Data::Page> object for the current resultset. Only makes
sense for queries with a C<page> attribute.

=cut

sub pager {
  my ($self) = @_;
  my $attrs = $self->{attrs};
  croak "Can't create pager for non-paged rs" unless $self->{page};
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

Creates a result in the resultset's result class.

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
  my $obj = $self->{source}->result_class->new(\%new);
  $obj->result_source($self->{source}) if $obj->can('result_source');
  $obj;
}

=head2 create(\%vals)

Inserts a record into the resultset and returns the object.

Effectively a shortcut for C<< ->new_result(\%vals)->insert >>.

=cut

sub create {
  my ($self, $attrs) = @_;
  $self->{source}->result_class->throw( "create needs a hashref" ) unless ref $attrs eq 'HASH';
  return $self->new_result($attrs)->insert;
}

=head2 find_or_create(\%vals, \%attrs?)

  $class->find_or_create({ key => $val, ... });

Searches for a record matching the search condition; if it doesn't find one,    
creates one and returns that instead.                                           

  my $cd = $schema->resultset('CD')->find_or_create({
    cdid   => 5,
    artist => 'Massive Attack',
    title  => 'Mezzanine',
    year   => 2005,
  });

Also takes an optional C<key> attribute, to search by a specific key or unique
constraint. For example:

  my $cd = $schema->resultset('CD')->find_or_create(
    {
      artist => 'Massive Attack',
      title  => 'Mezzanine',
    },
    { key => 'artist_title' }
  );

See also L</find> and L</update_or_create>.

=cut

sub find_or_create {
  my $self     = shift;
  my $attrs    = (@_ > 1 && ref $_[$#_] eq 'HASH' ? pop(@_) : {});
  my $hash     = ref $_[0] eq "HASH" ? shift : {@_};
  my $exists   = $self->find($hash, $attrs);
  return defined($exists) ? $exists : $self->create($hash);
}

=head2 update_or_create

  $class->update_or_create({ key => $val, ... });

First, search for an existing row matching one of the unique constraints
(including the primary key) on the source of this resultset.  If a row is
found, update it with the other given column values.  Otherwise, create a new
row.

Takes an optional C<key> attribute to search on a specific unique constraint.
For example:

  # In your application
  my $cd = $schema->resultset('CD')->update_or_create(
    {
      artist => 'Massive Attack',
      title  => 'Mezzanine',
      year   => 1998,
    },
    { key => 'artist_title' }
  );

If no C<key> is specified, it searches on all unique constraints defined on the
source, including the primary key.

If the C<key> is specified as C<primary>, search only on the primary key.

See also L</find> and L</find_or_create>.

=cut

sub update_or_create {
  my $self = shift;

  my $attrs = (@_ > 1 && ref $_[$#_] eq 'HASH' ? pop(@_) : {});
  my $hash  = ref $_[0] eq "HASH" ? shift : {@_};

  my %unique_constraints = $self->{source}->unique_constraints;
  my @constraint_names   = (exists $attrs->{key}
                            ? ($attrs->{key})
                            : keys %unique_constraints);

  my @unique_hashes;
  foreach my $name (@constraint_names) {
    my @unique_cols = @{ $unique_constraints{$name} };
    my %unique_hash =
      map  { $_ => $hash->{$_} }
      grep { exists $hash->{$_} }
      @unique_cols;

    push @unique_hashes, \%unique_hash
      if (scalar keys %unique_hash == scalar @unique_cols);
  }

  my $row;
  if (@unique_hashes) {
    $row = $self->search(\@unique_hashes, { rows => 1 })->first;
    if ($row) {
      $row->set_columns($hash);
      $row->update;
    }
  }

  unless ($row) {
    $row = $self->create($hash);
  }

  return $row;
}

=head1 ATTRIBUTES

The resultset takes various attributes that modify its behavior. Here's an
overview of them:

=head2 order_by

Which column(s) to order the results by. This is currently passed through
directly to SQL, so you can give e.g. C<foo DESC> for a descending order.

=head2 cols (arrayref)

Shortcut to request a particular set of columns to be retrieved.  Adds
C<me.> onto the start of any column without a C<.> in it and sets C<select>
from that, then auto-populates C<as> from C<select> as normal.

=head2 select (arrayref)

Indicates which columns should be selected from the storage. You can use
column names, or in the case of RDBMS back ends, function or stored procedure
names:

  $rs = $schema->resultset('Foo')->search(
    {},
    {
      select => {
        'column_name',
        { count => 'column_to_count' },
        { sum => 'column_to_sum' }
      }
    }
  );

When you use function/stored procedure names and do not supply an C<as>
attribute, the column names returned are storage-dependent. E.g. MySQL would
return a column named C<count(column_to_count)> in the above example.

=head2 as (arrayref)

Indicates column names for object inflation. This is used in conjunction with
C<select>, usually when C<select> contains one or more function or stored
procedure names:

  $rs = $schema->resultset('Foo')->search(
    {},
    {
      select => {
        'column1',
        { count => 'column2' }
      },
      as => [qw/ column1 column2_count /]
    }
  );

  my $foo = $rs->first(); # get the first Foo

If the object against which the search is performed already has an accessor
matching a column name specified in C<as>, the value can be retrieved using
the accessor as normal:

  my $column1 = $foo->column1();

If on the other hand an accessor does not exist in the object, you need to
use C<get_column> instead:

  my $column2_count = $foo->get_column('column2_count');

You can create your own accessors if required - see
L<DBIx::Class::Manual::Cookbook> for details.

=head2 join

Contains a list of relationships that should be joined for this query.  For
example:

  # Get CDs by Nine Inch Nails
  my $rs = $schema->resultset('CD')->search(
    { 'artist.name' => 'Nine Inch Nails' },
    { join => 'artist' }
  );

Can also contain a hash reference to refer to the other relation's relations.
For example:

  package MyApp::Schema::Track;
  use base qw/DBIx::Class/;
  __PACKAGE__->table('track');
  __PACKAGE__->add_columns(qw/trackid cd position title/);
  __PACKAGE__->set_primary_key('trackid');
  __PACKAGE__->belongs_to(cd => 'MyApp::Schema::CD');
  1;

  # In your application
  my $rs = $schema->resultset('Artist')->search(
    { 'track.title' => 'Teardrop' },
    {
      join     => { cd => 'track' },
      order_by => 'artist.name',
    }
  );

If you want to fetch the columns from the related table as well, see
C<prefetch> below.

=head2 prefetch

Contains a list of relationships that should be fetched along with the main 
query (when they are accessed afterwards they will have already been
"prefetched").  This is useful for when you know you will need the related
objects, because it saves a query.  Currently limited to prefetching
one relationship deep, so unlike C<join>, prefetch must be an arrayref.

=head2 from (arrayref)

The C<from> attribute gives you manual control over the C<FROM> clause of SQL
statements generated by L<DBIx::Class>, allowing you to express custom C<JOIN>
clauses.

NOTE: Use this on your own risk.  This allows you to shoot off your foot!
C<join> will usually do what you need and it is strongly recommended that you
avoid using C<from> unless you cannot achieve the desired result using C<join>.

In simple terms, C<from> works as follows:

    [
        { <alias> => <table>, -join-type => 'inner|left|right' }
        [] # nested JOIN (optional)
        { <table.column> = <foreign_table.foreign_key> }
    ]

    JOIN
        <alias> <table>
        [JOIN ...]
    ON <table.column> = <foreign_table.foreign_key>

An easy way to follow the examples below is to remember the following:

    Anything inside "[]" is a JOIN
    Anything inside "{}" is a condition for the enclosing JOIN

The following examples utilize a "person" table in a family tree application.
In order to express parent->child relationships, this table is self-joined:

    # Person->belongs_to('father' => 'Person');
    # Person->belongs_to('mother' => 'Person');

C<from> can be used to nest joins. Here we return all children with a father,
then search against all mothers of those children:

  $rs = $schema->resultset('Person')->search(
      {},
      {
          alias => 'mother', # alias columns in accordance with "from"
          from => [
              { mother => 'person' },
              [
                  [
                      { child => 'person' },
                      [
                          { father => 'person' },
                          { 'father.person_id' => 'child.father_id' }
                      ]
                  ],
                  { 'mother.person_id' => 'child.mother_id' }
              ],                
          ]
      },
  );

  # Equivalent SQL:
  # SELECT mother.* FROM person mother
  # JOIN (
  #   person child
  #   JOIN person father
  #   ON ( father.person_id = child.father_id )
  # )
  # ON ( mother.person_id = child.mother_id )

The type of any join can be controlled manually. To search against only people
with a father in the person table, we could explicitly use C<INNER JOIN>:

    $rs = $schema->resultset('Person')->search(
        {},
        {
            alias => 'child', # alias columns in accordance with "from"
            from => [
                { child => 'person' },
                [
                    { father => 'person', -join-type => 'inner' },
                    { 'father.id' => 'child.father_id' }
                ],
            ]
        },
    );

    # Equivalent SQL:
    # SELECT child.* FROM person child
    # INNER JOIN person father ON child.father_id = father.id

=head2 page

For a paged resultset, specifies which page to retrieve.  Leave unset
for an unpaged resultset.

=head2 rows

For a paged resultset, how many rows per page:

  rows => 10

Can also be used to simulate an SQL C<LIMIT>.

=head2 group_by (arrayref)

A arrayref of columns to group by. Can include columns of joined tables. Note
note that L</count> doesn't work on grouped resultsets.

  group_by => [qw/ column1 column2 ... /]

=head2 distinct

Set to 1 to group by all columns.

For more examples of using these attributes, see
L<DBIx::Class::Manual::Cookbook>.

=cut

1;
