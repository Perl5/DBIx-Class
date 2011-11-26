package DBIx::Class::ResultSet;

use strict;
use warnings;
use base qw/DBIx::Class/;
use DBIx::Class::Carp;
use DBIx::Class::Exception;
use DBIx::Class::ResultSetColumn;
use Scalar::Util qw/blessed weaken/;
use Try::Tiny;
use Data::Compare (); # no imports!!! guard against insane architecture

# not importing first() as it will clash with our own method
use List::Util ();

BEGIN {
  # De-duplication in _merge_attr() is disabled, but left in for reference
  # (the merger is used for other things that ought not to be de-duped)
  *__HM_DEDUP = sub () { 0 };
}

use namespace::clean;

use overload
        '0+'     => "count",
        'bool'   => "_bool",
        fallback => 1;

__PACKAGE__->mk_group_accessors('simple' => qw/_result_class result_source/);

=head1 NAME

DBIx::Class::ResultSet - Represents a query used for fetching a set of results.

=head1 SYNOPSIS

  my $users_rs   = $schema->resultset('User');
  while( $user = $users_rs->next) {
    print $user->username;
  }

  my $registered_users_rs   = $schema->resultset('User')->search({ registered => 1 });
  my @cds_in_2005 = $schema->resultset('CD')->search({ year => 2005 })->all();

=head1 DESCRIPTION

A ResultSet is an object which stores a set of conditions representing
a query. It is the backbone of DBIx::Class (i.e. the really
important/useful bit).

No SQL is executed on the database when a ResultSet is created, it
just stores all the conditions needed to create the query.

A basic ResultSet representing the data of an entire table is returned
by calling C<resultset> on a L<DBIx::Class::Schema> and passing in a
L<Source|DBIx::Class::Manual::Glossary/Source> name.

  my $users_rs = $schema->resultset('User');

A new ResultSet is returned from calling L</search> on an existing
ResultSet. The new one will contain all the conditions of the
original, plus any new conditions added in the C<search> call.

A ResultSet also incorporates an implicit iterator. L</next> and L</reset>
can be used to walk through all the L<DBIx::Class::Row>s the ResultSet
represents.

The query that the ResultSet represents is B<only> executed against
the database when these methods are called:
L</find>, L</next>, L</all>, L</first>, L</single>, L</count>.

If a resultset is used in a numeric context it returns the L</count>.
However, if it is used in a boolean context it is B<always> true.  So if
you want to check if a resultset has any results, you must use C<if $rs
!= 0>.

=head1 EXAMPLES

=head2 Chaining resultsets

Let's say you've got a query that needs to be run to return some data
to the user. But, you have an authorization system in place that
prevents certain users from seeing certain information. So, you want
to construct the basic query in one method, but add constraints to it in
another.

  sub get_data {
    my $self = shift;
    my $request = $self->get_request; # Get a request object somehow.
    my $schema = $self->result_source->schema;

    my $cd_rs = $schema->resultset('CD')->search({
      title => $request->param('title'),
      year => $request->param('year'),
    });

    $cd_rs = $self->apply_security_policy( $cd_rs );

    return $cd_rs->all();
  }

  sub apply_security_policy {
    my $self = shift;
    my ($rs) = @_;

    return $rs->search({
      subversive => 0,
    });
  }

=head3 Resolving conditions and attributes

When a resultset is chained from another resultset, conditions and
attributes with the same keys need resolving.

L</join>, L</prefetch>, L</+select>, L</+as> attributes are merged
into the existing ones from the original resultset.

The L</where> and L</having> attributes, and any search conditions, are
merged with an SQL C<AND> to the existing condition from the original
resultset.

All other attributes are overridden by any new ones supplied in the
search attributes.

=head2 Multiple queries

Since a resultset just defines a query, you can do all sorts of
things with it with the same object.

  # Don't hit the DB yet.
  my $cd_rs = $schema->resultset('CD')->search({
    title => 'something',
    year => 2009,
  });

  # Each of these hits the DB individually.
  my $count = $cd_rs->count;
  my $most_recent = $cd_rs->get_column('date_released')->max();
  my @records = $cd_rs->all;

And it's not just limited to SELECT statements.

  $cd_rs->delete();

This is even cooler:

  $cd_rs->create({ artist => 'Fred' });

Which is the same as:

  $schema->resultset('CD')->create({
    title => 'something',
    year => 2009,
    artist => 'Fred'
  });

See: L</search>, L</count>, L</get_column>, L</all>, L</create>.

=head1 METHODS

=head2 new

=over 4

=item Arguments: $source, \%$attrs

=item Return Value: $rs

=back

The resultset constructor. Takes a source object (usually a
L<DBIx::Class::ResultSourceProxy::Table>) and an attribute hash (see
L</ATTRIBUTES> below).  Does not perform any queries -- these are
executed as needed by the other methods.

Generally you won't need to construct a resultset manually.  You'll
automatically get one from e.g. a L</search> called in scalar context:

  my $rs = $schema->resultset('CD')->search({ title => '100th Window' });

IMPORTANT: If called on an object, proxies to new_result instead so

  my $cd = $schema->resultset('CD')->new({ title => 'Spoon' });

will return a CD object, not a ResultSet.

=cut

sub new {
  my $class = shift;
  return $class->new_result(@_) if ref $class;

  my ($source, $attrs) = @_;
  $source = $source->resolve
    if $source->isa('DBIx::Class::ResultSourceHandle');
  $attrs = { %{$attrs||{}} };

  if ($attrs->{page}) {
    $attrs->{rows} ||= 10;
  }

  $attrs->{alias} ||= 'me';

  my $self = bless {
    result_source => $source,
    cond => $attrs->{where},
    pager => undef,
    attrs => $attrs,
  }, $class;

  # if there is a dark selector, this means we are already in a
  # chain and the cleanup/sanification was taken care of by
  # _search_rs already
  $self->_normalize_selection($attrs)
    unless $attrs->{_dark_selector};

  $self->result_class(
    $attrs->{result_class} || $source->result_class
  );

  $self;
}

=head2 search

=over 4

=item Arguments: $cond, \%attrs?

=item Return Value: $resultset (scalar context) ||  @row_objs (list context)

=back

  my @cds    = $cd_rs->search({ year => 2001 }); # "... WHERE year = 2001"
  my $new_rs = $cd_rs->search({ year => 2005 });

  my $new_rs = $cd_rs->search([ { year => 2005 }, { year => 2004 } ]);
                 # year = 2005 OR year = 2004

In list context, C<< ->all() >> is called implicitly on the resultset, thus
returning a list of row objects instead. To avoid that, use L</search_rs>.

If you need to pass in additional attributes but no additional condition,
call it as C<search(undef, \%attrs)>.

  # "SELECT name, artistid FROM $artist_table"
  my @all_artists = $schema->resultset('Artist')->search(undef, {
    columns => [qw/name artistid/],
  });

For a list of attributes that can be passed to C<search>, see
L</ATTRIBUTES>. For more examples of using this function, see
L<Searching|DBIx::Class::Manual::Cookbook/Searching>. For a complete
documentation for the first argument, see L<SQL::Abstract>
and its extension L<DBIx::Class::SQLMaker>.

For more help on using joins with search, see L<DBIx::Class::Manual::Joining>.

=head3 CAVEAT

Note that L</search> does not process/deflate any of the values passed in the
L<SQL::Abstract>-compatible search condition structure. This is unlike other
condition-bound methods L</new>, L</create> and L</find>. The user must ensure
manually that any value passed to this method will stringify to something the
RDBMS knows how to deal with. A notable example is the handling of L<DateTime>
objects, for more info see:
L<DBIx::Class::Manual::Cookbook/Formatting_DateTime_objects_in_queries>.

=cut

sub search {
  my $self = shift;
  my $rs = $self->search_rs( @_ );

  if (wantarray) {
    return $rs->all;
  }
  elsif (defined wantarray) {
    return $rs;
  }
  else {
    # we can be called by a relationship helper, which in
    # turn may be called in void context due to some braindead
    # overload or whatever else the user decided to be clever
    # at this particular day. Thus limit the exception to
    # external code calls only
    $self->throw_exception ('->search is *not* a mutator, calling it in void context makes no sense')
      if (caller)[0] !~ /^\QDBIx::Class::/;

    return ();
  }
}

=head2 search_rs

=over 4

=item Arguments: $cond, \%attrs?

=item Return Value: $resultset

=back

This method does the same exact thing as search() except it will
always return a resultset, even in list context.

=cut

sub search_rs {
  my $self = shift;

  # Special-case handling for (undef, undef).
  if ( @_ == 2 && !defined $_[1] && !defined $_[0] ) {
    @_ = ();
  }

  my $call_attrs = {};
  if (@_ > 1) {
    if (ref $_[-1] eq 'HASH') {
      # copy for _normalize_selection
      $call_attrs = { %{ pop @_ } };
    }
    elsif (! defined $_[-1] ) {
      pop @_;   # search({}, undef)
    }
  }

  # see if we can keep the cache (no $rs changes)
  my $cache;
  my %safe = (alias => 1, cache => 1);
  if ( ! List::Util::first { !$safe{$_} } keys %$call_attrs and (
    ! defined $_[0]
      or
    ref $_[0] eq 'HASH' && ! keys %{$_[0]}
      or
    ref $_[0] eq 'ARRAY' && ! @{$_[0]}
  )) {
    $cache = $self->get_cache;
  }

  my $rsrc = $self->result_source;

  my $old_attrs = { %{$self->{attrs}} };
  my $old_having = delete $old_attrs->{having};
  my $old_where = delete $old_attrs->{where};

  my $new_attrs = { %$old_attrs };

  # take care of call attrs (only if anything is changing)
  if (keys %$call_attrs) {

    my @selector_attrs = qw/select as columns cols +select +as +columns include_columns/;

    # reset the current selector list if new selectors are supplied
    if (List::Util::first { exists $call_attrs->{$_} } qw/columns cols select as/) {
      delete @{$old_attrs}{(@selector_attrs, '_dark_selector')};
    }

    # Normalize the new selector list (operates on the passed-in attr structure)
    # Need to do it on every chain instead of only once on _resolved_attrs, in
    # order to allow detection of empty vs partial 'as'
    $call_attrs->{_dark_selector} = $old_attrs->{_dark_selector}
      if $old_attrs->{_dark_selector};
    $self->_normalize_selection ($call_attrs);

    # start with blind overwriting merge, exclude selector attrs
    $new_attrs = { %{$old_attrs}, %{$call_attrs} };
    delete @{$new_attrs}{@selector_attrs};

    for (@selector_attrs) {
      $new_attrs->{$_} = $self->_merge_attr($old_attrs->{$_}, $call_attrs->{$_})
        if ( exists $old_attrs->{$_} or exists $call_attrs->{$_} );
    }

    # older deprecated name, use only if {columns} is not there
    if (my $c = delete $new_attrs->{cols}) {
      if ($new_attrs->{columns}) {
        carp "Resultset specifies both the 'columns' and the legacy 'cols' attributes - ignoring 'cols'";
      }
      else {
        $new_attrs->{columns} = $c;
      }
    }


    # join/prefetch use their own crazy merging heuristics
    foreach my $key (qw/join prefetch/) {
      $new_attrs->{$key} = $self->_merge_joinpref_attr($old_attrs->{$key}, $call_attrs->{$key})
        if exists $call_attrs->{$key};
    }

    # stack binds together
    $new_attrs->{bind} = [ @{ $old_attrs->{bind} || [] }, @{ $call_attrs->{bind} || [] } ];
  }


  # rip apart the rest of @_, parse a condition
  my $call_cond = do {

    if (ref $_[0] eq 'HASH') {
      (keys %{$_[0]}) ? $_[0] : undef
    }
    elsif (@_ == 1) {
      $_[0]
    }
    elsif (@_ % 2) {
      $self->throw_exception('Odd number of arguments to search')
    }
    else {
      +{ @_ }
    }

  } if @_;

  if( @_ > 1 and ! $rsrc->result_class->isa('DBIx::Class::CDBICompat') ) {
    carp_unique 'search( %condition ) is deprecated, use search( \%condition ) instead';
  }

  for ($old_where, $call_cond) {
    if (defined $_) {
      $new_attrs->{where} = $self->_stack_cond (
        $_, $new_attrs->{where}
      );
    }
  }

  if (defined $old_having) {
    $new_attrs->{having} = $self->_stack_cond (
      $old_having, $new_attrs->{having}
    )
  }

  my $rs = (ref $self)->new($rsrc, $new_attrs);

  $rs->set_cache($cache) if ($cache);

  return $rs;
}

my $dark_sel_dumper;
sub _normalize_selection {
  my ($self, $attrs) = @_;

  # legacy syntax
  $attrs->{'+columns'} = $self->_merge_attr($attrs->{'+columns'}, delete $attrs->{include_columns})
    if exists $attrs->{include_columns};

  # columns are always placed first, however 

  # Keep the X vs +X separation until _resolved_attrs time - this allows to
  # delay the decision on whether to use a default select list ($rsrc->columns)
  # allowing stuff like the remove_columns helper to work
  #
  # select/as +select/+as pairs need special handling - the amount of select/as
  # elements in each pair does *not* have to be equal (think multicolumn
  # selectors like distinct(foo, bar) ). If the selector is bare (no 'as'
  # supplied at all) - try to infer the alias, either from the -as parameter
  # of the selector spec, or use the parameter whole if it looks like a column
  # name (ugly legacy heuristic). If all fails - leave the selector bare (which
  # is ok as well), but make sure no more additions to the 'as' chain take place
  for my $pref ('', '+') {

    my ($sel, $as) = map {
      my $key = "${pref}${_}";

      my $val = [ ref $attrs->{$key} eq 'ARRAY'
        ? @{$attrs->{$key}}
        : $attrs->{$key} || ()
      ];
      delete $attrs->{$key};
      $val;
    } qw/select as/;

    if (! @$as and ! @$sel ) {
      next;
    }
    elsif (@$as and ! @$sel) {
      $self->throw_exception(
        "Unable to handle ${pref}as specification (@$as) without a corresponding ${pref}select"
      );
    }
    elsif( ! @$as ) {
      # no as part supplied at all - try to deduce (unless explicit end of named selection is declared)
      # if any @$as has been supplied we assume the user knows what (s)he is doing
      # and blindly keep stacking up pieces
      unless ($attrs->{_dark_selector}) {
        SELECTOR:
        for (@$sel) {
          if ( ref $_ eq 'HASH' and exists $_->{-as} ) {
            push @$as, $_->{-as};
          }
          # assume any plain no-space, no-parenthesis string to be a column spec
          # FIXME - this is retarded but is necessary to support shit like 'count(foo)'
          elsif ( ! ref $_ and $_ =~ /^ [^\s\(\)]+ $/x) {
            push @$as, $_;
          }
          # if all else fails - raise a flag that no more aliasing will be allowed
          else {
            $attrs->{_dark_selector} = {
              plus_stage => $pref,
              string => ($dark_sel_dumper ||= do {
                  require Data::Dumper::Concise;
                  Data::Dumper::Concise::DumperObject()->Indent(0);
                })->Values([$_])->Dump
              ,
            };
            last SELECTOR;
          }
        }
      }
    }
    elsif (@$as < @$sel) {
      $self->throw_exception(
        "Unable to handle an ${pref}as specification (@$as) with less elements than the corresponding ${pref}select"
      );
    }
    elsif ($pref and $attrs->{_dark_selector}) {
      $self->throw_exception(
        "Unable to process named '+select', resultset contains an unnamed selector $attrs->{_dark_selector}{string}"
      );
    }


    # merge result
    $attrs->{"${pref}select"} = $self->_merge_attr($attrs->{"${pref}select"}, $sel);
    $attrs->{"${pref}as"} = $self->_merge_attr($attrs->{"${pref}as"}, $as);
  }
}

sub _stack_cond {
  my ($self, $left, $right) = @_;

  # collapse single element top-level conditions
  # (single pass only, unlikely to need recursion)
  for ($left, $right) {
    if (ref $_ eq 'ARRAY') {
      if (@$_ == 0) {
        $_ = undef;
      }
      elsif (@$_ == 1) {
        $_ = $_->[0];
      }
    }
    elsif (ref $_ eq 'HASH') {
      my ($first, $more) = keys %$_;

      # empty hash
      if (! defined $first) {
        $_ = undef;
      }
      # one element hash
      elsif (! defined $more) {
        if ($first eq '-and' and ref $_->{'-and'} eq 'HASH') {
          $_ = $_->{'-and'};
        }
        elsif ($first eq '-or' and ref $_->{'-or'} eq 'ARRAY') {
          $_ = $_->{'-or'};
        }
      }
    }
  }

  # merge hashes with weeding out of duplicates (simple cases only)
  if (ref $left eq 'HASH' and ref $right eq 'HASH') {

    # shallow copy to destroy
    $right = { %$right };
    for (grep { exists $right->{$_} } keys %$left) {
      # the use of eq_deeply here is justified - the rhs of an
      # expression can contain a lot of twisted weird stuff
      delete $right->{$_} if Data::Compare::Compare( $left->{$_}, $right->{$_} );
    }

    $right = undef unless keys %$right;
  }


  if (defined $left xor defined $right) {
    return defined $left ? $left : $right;
  }
  elsif (! defined $left) {
    return undef;
  }
  else {
    return { -and => [ $left, $right ] };
  }
}

=head2 search_literal

=over 4

=item Arguments: $sql_fragment, @bind_values

=item Return Value: $resultset (scalar context) || @row_objs (list context)

=back

  my @cds   = $cd_rs->search_literal('year = ? AND title = ?', qw/2001 Reload/);
  my $newrs = $artist_rs->search_literal('name = ?', 'Metallica');

Pass a literal chunk of SQL to be added to the conditional part of the
resultset query.

CAVEAT: C<search_literal> is provided for Class::DBI compatibility and should
only be used in that context. C<search_literal> is a convenience method.
It is equivalent to calling $schema->search(\[]), but if you want to ensure
columns are bound correctly, use C<search>.

Example of how to use C<search> instead of C<search_literal>

  my @cds = $cd_rs->search_literal('cdid = ? AND (artist = ? OR artist = ?)', (2, 1, 2));
  my @cds = $cd_rs->search(\[ 'cdid = ? AND (artist = ? OR artist = ?)', [ 'cdid', 2 ], [ 'artist', 1 ], [ 'artist', 2 ] ]);


See L<DBIx::Class::Manual::Cookbook/Searching> and
L<DBIx::Class::Manual::FAQ/Searching> for searching techniques that do not
require C<search_literal>.

=cut

sub search_literal {
  my ($self, $sql, @bind) = @_;
  my $attr;
  if ( @bind && ref($bind[-1]) eq 'HASH' ) {
    $attr = pop @bind;
  }
  return $self->search(\[ $sql, map [ __DUMMY__ => $_ ], @bind ], ($attr || () ));
}

=head2 find

=over 4

=item Arguments: \%columns_values | @pk_values, \%attrs?

=item Return Value: $row_object | undef

=back

Finds and returns a single row based on supplied criteria. Takes either a
hashref with the same format as L</create> (including inference of foreign
keys from related objects), or a list of primary key values in the same
order as the L<primary columns|DBIx::Class::ResultSource/primary_columns>
declaration on the L</result_source>.

In either case an attempt is made to combine conditions already existing on
the resultset with the condition passed to this method.

To aid with preparing the correct query for the storage you may supply the
C<key> attribute, which is the name of a
L<unique constraint|DBIx::Class::ResultSource/add_unique_constraint> (the
unique constraint corresponding to the
L<primary columns|DBIx::Class::ResultSource/primary_columns> is always named
C<primary>). If the C<key> attribute has been supplied, and DBIC is unable
to construct a query that satisfies the named unique constraint fully (
non-NULL values for each column member of the constraint) an exception is
thrown.

If no C<key> is specified, the search is carried over all unique constraints
which are fully defined by the available condition.

If no such constraint is found, C<find> currently defaults to a simple
C<< search->(\%column_values) >> which may or may not do what you expect.
Note that this fallback behavior may be deprecated in further versions. If
you need to search with arbitrary conditions - use L</search>. If the query
resulting from this fallback produces more than one row, a warning to the
effect is issued, though only the first row is constructed and returned as
C<$row_object>.

In addition to C<key>, L</find> recognizes and applies standard
L<resultset attributes|/ATTRIBUTES> in the same way as L</search> does.

Note that if you have extra concerns about the correctness of the resulting
query you need to specify the C<key> attribute and supply the entire condition
as an argument to find (since it is not always possible to perform the
combination of the resultset condition with the supplied one, especially if
the resultset condition contains literal sql).

For example, to find a row by its primary key:

  my $cd = $schema->resultset('CD')->find(5);

You can also find a row by a specific unique constraint:

  my $cd = $schema->resultset('CD')->find(
    {
      artist => 'Massive Attack',
      title  => 'Mezzanine',
    },
    { key => 'cd_artist_title' }
  );

See also L</find_or_create> and L</update_or_create>.

=cut

sub find {
  my $self = shift;
  my $attrs = (@_ > 1 && ref $_[$#_] eq 'HASH' ? pop(@_) : {});

  my $rsrc = $self->result_source;

  my $constraint_name;
  if (exists $attrs->{key}) {
    $constraint_name = defined $attrs->{key}
      ? $attrs->{key}
      : $self->throw_exception("An undefined 'key' resultset attribute makes no sense")
    ;
  }

  # Parse out the condition from input
  my $call_cond;

  if (ref $_[0] eq 'HASH') {
    $call_cond = { %{$_[0]} };
  }
  else {
    # if only values are supplied we need to default to 'primary'
    $constraint_name = 'primary' unless defined $constraint_name;

    my @c_cols = $rsrc->unique_constraint_columns($constraint_name);

    $self->throw_exception(
      "No constraint columns, maybe a malformed '$constraint_name' constraint?"
    ) unless @c_cols;

    $self->throw_exception (
      'find() expects either a column/value hashref, or a list of values '
    . "corresponding to the columns of the specified unique constraint '$constraint_name'"
    ) unless @c_cols == @_;

    $call_cond = {};
    @{$call_cond}{@c_cols} = @_;
  }

  my %related;
  for my $key (keys %$call_cond) {
    if (
      my $keyref = ref($call_cond->{$key})
        and
      my $relinfo = $rsrc->relationship_info($key)
    ) {
      my $val = delete $call_cond->{$key};

      next if $keyref eq 'ARRAY'; # has_many for multi_create

      my $rel_q = $rsrc->_resolve_condition(
        $relinfo->{cond}, $val, $key, $key
      );
      die "Can't handle complex relationship conditions in find" if ref($rel_q) ne 'HASH';
      @related{keys %$rel_q} = values %$rel_q;
    }
  }

  # relationship conditions take precedence (?)
  @{$call_cond}{keys %related} = values %related;

  my $alias = exists $attrs->{alias} ? $attrs->{alias} : $self->{attrs}{alias};
  my $final_cond;
  if (defined $constraint_name) {
    $final_cond = $self->_qualify_cond_columns (

      $self->_build_unique_cond (
        $constraint_name,
        $call_cond,
      ),

      $alias,
    );
  }
  elsif ($self->{attrs}{accessor} and $self->{attrs}{accessor} eq 'single') {
    # This means that we got here after a merger of relationship conditions
    # in ::Relationship::Base::search_related (the row method), and furthermore
    # the relationship is of the 'single' type. This means that the condition
    # provided by the relationship (already attached to $self) is sufficient,
    # as there can be only one row in the database that would satisfy the
    # relationship
  }
  else {
    # no key was specified - fall down to heuristics mode:
    # run through all unique queries registered on the resultset, and
    # 'OR' all qualifying queries together
    my (@unique_queries, %seen_column_combinations);
    for my $c_name ($rsrc->unique_constraint_names) {
      next if $seen_column_combinations{
        join "\x00", sort $rsrc->unique_constraint_columns($c_name)
      }++;

      push @unique_queries, try {
        $self->_build_unique_cond ($c_name, $call_cond, 'croak_on_nulls')
      } || ();
    }

    $final_cond = @unique_queries
      ? [ map { $self->_qualify_cond_columns($_, $alias) } @unique_queries ]
      : $self->_non_unique_find_fallback ($call_cond, $attrs)
    ;
  }

  # Run the query, passing the result_class since it should propagate for find
  my $rs = $self->search ($final_cond, {result_class => $self->result_class, %$attrs});
  if (keys %{$rs->_resolved_attrs->{collapse}}) {
    my $row = $rs->next;
    carp "Query returned more than one row" if $rs->next;
    return $row;
  }
  else {
    return $rs->single;
  }
}

# This is a stop-gap method as agreed during the discussion on find() cleanup:
# http://lists.scsys.co.uk/pipermail/dbix-class/2010-October/009535.html
#
# It is invoked when find() is called in legacy-mode with insufficiently-unique
# condition. It is provided for overrides until a saner way forward is devised
#
# *NOTE* This is not a public method, and it's *GUARANTEED* to disappear down
# the road. Please adjust your tests accordingly to catch this situation early
# DBIx::Class::ResultSet->can('_non_unique_find_fallback') is reasonable
#
# The method will not be removed without an adequately complete replacement
# for strict-mode enforcement
sub _non_unique_find_fallback {
  my ($self, $cond, $attrs) = @_;

  return $self->_qualify_cond_columns(
    $cond,
    exists $attrs->{alias}
      ? $attrs->{alias}
      : $self->{attrs}{alias}
  );
}


sub _qualify_cond_columns {
  my ($self, $cond, $alias) = @_;

  my %aliased = %$cond;
  for (keys %aliased) {
    $aliased{"$alias.$_"} = delete $aliased{$_}
      if $_ !~ /\./;
  }

  return \%aliased;
}

sub _build_unique_cond {
  my ($self, $constraint_name, $extra_cond, $croak_on_null) = @_;

  my @c_cols = $self->result_source->unique_constraint_columns($constraint_name);

  # combination may fail if $self->{cond} is non-trivial
  my ($final_cond) = try {
    $self->_merge_with_rscond ($extra_cond)
  } catch {
    +{ %$extra_cond }
  };

  # trim out everything not in $columns
  $final_cond = { map {
    exists $final_cond->{$_}
      ? ( $_ => $final_cond->{$_} )
      : ()
  } @c_cols };

  if (my @missing = grep
    { ! ($croak_on_null ? defined $final_cond->{$_} : exists $final_cond->{$_}) }
    (@c_cols)
  ) {
    $self->throw_exception( sprintf ( "Unable to satisfy requested constraint '%s', no values for column(s): %s",
      $constraint_name,
      join (', ', map { "'$_'" } @missing),
    ) );
  }

  if (
    !$croak_on_null
      and
    !$ENV{DBIC_NULLABLE_KEY_NOWARN}
      and
    my @undefs = grep { ! defined $final_cond->{$_} } (keys %$final_cond)
  ) {
    carp_unique ( sprintf (
      "NULL/undef values supplied for requested unique constraint '%s' (NULL "
    . 'values in column(s): %s). This is almost certainly not what you wanted, '
    . 'though you can set DBIC_NULLABLE_KEY_NOWARN to disable this warning.',
      $constraint_name,
      join (', ', map { "'$_'" } @undefs),
    ));
  }

  return $final_cond;
}

=head2 search_related

=over 4

=item Arguments: $rel, $cond, \%attrs?

=item Return Value: $new_resultset (scalar context) || @row_objs (list context)

=back

  $new_rs = $cd_rs->search_related('artist', {
    name => 'Emo-R-Us',
  });

Searches the specified relationship, optionally specifying a condition and
attributes for matching records. See L</ATTRIBUTES> for more information.

In list context, C<< ->all() >> is called implicitly on the resultset, thus
returning a list of row objects instead. To avoid that, use L</search_related_rs>.

See also L</search_related_rs>.

=cut

sub search_related {
  return shift->related_resultset(shift)->search(@_);
}

=head2 search_related_rs

This method works exactly the same as search_related, except that
it guarantees a resultset, even in list context.

=cut

sub search_related_rs {
  return shift->related_resultset(shift)->search_rs(@_);
}

=head2 cursor

=over 4

=item Arguments: none

=item Return Value: $cursor

=back

Returns a storage-driven cursor to the given resultset. See
L<DBIx::Class::Cursor> for more information.

=cut

sub cursor {
  my ($self) = @_;

  my $attrs = $self->_resolved_attrs_copy;

  return $self->{cursor}
    ||= $self->result_source->storage->select($attrs->{from}, $attrs->{select},
          $attrs->{where},$attrs);
}

=head2 single

=over 4

=item Arguments: $cond?

=item Return Value: $row_object | undef

=back

  my $cd = $schema->resultset('CD')->single({ year => 2001 });

Inflates the first result without creating a cursor if the resultset has
any records in it; if not returns C<undef>. Used by L</find> as a lean version
of L</search>.

While this method can take an optional search condition (just like L</search>)
being a fast-code-path it does not recognize search attributes. If you need to
add extra joins or similar, call L</search> and then chain-call L</single> on the
L<DBIx::Class::ResultSet> returned.

=over

=item B<Note>

As of 0.08100, this method enforces the assumption that the preceding
query returns only one row. If more than one row is returned, you will receive
a warning:

  Query returned more than one row

In this case, you should be using L</next> or L</find> instead, or if you really
know what you are doing, use the L</rows> attribute to explicitly limit the size
of the resultset.

This method will also throw an exception if it is called on a resultset prefetching
has_many, as such a prefetch implies fetching multiple rows from the database in
order to assemble the resulting object.

=back

=cut

sub single {
  my ($self, $where) = @_;
  if(@_ > 2) {
      $self->throw_exception('single() only takes search conditions, no attributes. You want ->search( $cond, $attrs )->single()');
  }

  my $attrs = $self->_resolved_attrs_copy;

  if (keys %{$attrs->{collapse}}) {
    $self->throw_exception(
      'single() can not be used on resultsets prefetching has_many. Use find( \%cond ) or next() instead'
    );
  }

  if ($where) {
    if (defined $attrs->{where}) {
      $attrs->{where} = {
        '-and' =>
            [ map { ref $_ eq 'ARRAY' ? [ -or => $_ ] : $_ }
               $where, delete $attrs->{where} ]
      };
    } else {
      $attrs->{where} = $where;
    }
  }

  my @data = $self->result_source->storage->select_single(
    $attrs->{from}, $attrs->{select},
    $attrs->{where}, $attrs
  );

  return (@data ? ($self->_construct_object(@data))[0] : undef);
}


# _collapse_query
#
# Recursively collapse the query, accumulating values for each column.

sub _collapse_query {
  my ($self, $query, $collapsed) = @_;

  $collapsed ||= {};

  if (ref $query eq 'ARRAY') {
    foreach my $subquery (@$query) {
      next unless ref $subquery;  # -or
      $collapsed = $self->_collapse_query($subquery, $collapsed);
    }
  }
  elsif (ref $query eq 'HASH') {
    if (keys %$query and (keys %$query)[0] eq '-and') {
      foreach my $subquery (@{$query->{-and}}) {
        $collapsed = $self->_collapse_query($subquery, $collapsed);
      }
    }
    else {
      foreach my $col (keys %$query) {
        my $value = $query->{$col};
        $collapsed->{$col}{$value}++;
      }
    }
  }

  return $collapsed;
}

=head2 get_column

=over 4

=item Arguments: $cond?

=item Return Value: $resultsetcolumn

=back

  my $max_length = $rs->get_column('length')->max;

Returns a L<DBIx::Class::ResultSetColumn> instance for a column of the ResultSet.

=cut

sub get_column {
  my ($self, $column) = @_;
  my $new = DBIx::Class::ResultSetColumn->new($self, $column);
  return $new;
}

=head2 search_like

=over 4

=item Arguments: $cond, \%attrs?

=item Return Value: $resultset (scalar context) || @row_objs (list context)

=back

  # WHERE title LIKE '%blue%'
  $cd_rs = $rs->search_like({ title => '%blue%'});

Performs a search, but uses C<LIKE> instead of C<=> as the condition. Note
that this is simply a convenience method retained for ex Class::DBI users.
You most likely want to use L</search> with specific operators.

For more information, see L<DBIx::Class::Manual::Cookbook>.

This method is deprecated and will be removed in 0.09. Use L</search()>
instead. An example conversion is:

  ->search_like({ foo => 'bar' });

  # Becomes

  ->search({ foo => { like => 'bar' } });

=cut

sub search_like {
  my $class = shift;
  carp_unique (
    'search_like() is deprecated and will be removed in DBIC version 0.09.'
   .' Instead use ->search({ x => { -like => "y%" } })'
   .' (note the outer pair of {}s - they are important!)'
  );
  my $attrs = (@_ > 1 && ref $_[$#_] eq 'HASH' ? pop(@_) : {});
  my $query = ref $_[0] eq 'HASH' ? { %{shift()} }: {@_};
  $query->{$_} = { 'like' => $query->{$_} } for keys %$query;
  return $class->search($query, { %$attrs });
}

=head2 slice

=over 4

=item Arguments: $first, $last

=item Return Value: $resultset (scalar context) || @row_objs (list context)

=back

Returns a resultset or object list representing a subset of elements from the
resultset slice is called on. Indexes are from 0, i.e., to get the first
three records, call:

  my ($one, $two, $three) = $rs->slice(0, 2);

=cut

sub slice {
  my ($self, $min, $max) = @_;
  my $attrs = {}; # = { %{ $self->{attrs} || {} } };
  $attrs->{offset} = $self->{attrs}{offset} || 0;
  $attrs->{offset} += $min;
  $attrs->{rows} = ($max ? ($max - $min + 1) : 1);
  return $self->search(undef, $attrs);
  #my $slice = (ref $self)->new($self->result_source, $attrs);
  #return (wantarray ? $slice->all : $slice);
}

=head2 next

=over 4

=item Arguments: none

=item Return Value: $result | undef

=back

Returns the next element in the resultset (C<undef> is there is none).

Can be used to efficiently iterate over records in the resultset:

  my $rs = $schema->resultset('CD')->search;
  while (my $cd = $rs->next) {
    print $cd->title;
  }

Note that you need to store the resultset object, and call C<next> on it.
Calling C<< resultset('Table')->next >> repeatedly will always return the
first record from the resultset.

=cut

sub next {
  my ($self) = @_;
  if (my $cache = $self->get_cache) {
    $self->{all_cache_position} ||= 0;
    return $cache->[$self->{all_cache_position}++];
  }
  if ($self->{attrs}{cache}) {
    delete $self->{pager};
    $self->{all_cache_position} = 1;
    return ($self->all)[0];
  }
  if ($self->{stashed_objects}) {
    my $obj = shift(@{$self->{stashed_objects}});
    delete $self->{stashed_objects} unless @{$self->{stashed_objects}};
    return $obj;
  }
  my @row = (
    exists $self->{stashed_row}
      ? @{delete $self->{stashed_row}}
      : $self->cursor->next
  );
  return undef unless (@row);
  my ($row, @more) = $self->_construct_object(@row);
  $self->{stashed_objects} = \@more if @more;
  return $row;
}

sub _construct_object {
  my ($self, @row) = @_;

  my $info = $self->_collapse_result($self->{_attrs}{as}, \@row)
    or return ();
  my @new = $self->result_class->inflate_result($self->result_source, @$info);
  @new = $self->{_attrs}{record_filter}->(@new)
    if exists $self->{_attrs}{record_filter};
  return @new;
}

sub _collapse_result {
  my ($self, $as_proto, $row) = @_;

  my @copy = @$row;

  # 'foo'         => [ undef, 'foo' ]
  # 'foo.bar'     => [ 'foo', 'bar' ]
  # 'foo.bar.baz' => [ 'foo.bar', 'baz' ]

  my @construct_as = map { [ (/^(?:(.*)\.)?([^.]+)$/) ] } @$as_proto;

  my %collapse = %{$self->{_attrs}{collapse}||{}};

  my @pri_index;

  # if we're doing collapsing (has_many prefetch) we need to grab records
  # until the PK changes, so fill @pri_index. if not, we leave it empty so
  # we know we don't have to bother.

  # the reason for not using the collapse stuff directly is because if you
  # had for e.g. two artists in a row with no cds, the collapse info for
  # both would be NULL (undef) so you'd lose the second artist

  # store just the index so we can check the array positions from the row
  # without having to contruct the full hash

  if (keys %collapse) {
    my %pri = map { ($_ => 1) } $self->result_source->_pri_cols;
    foreach my $i (0 .. $#construct_as) {
      next if defined($construct_as[$i][0]); # only self table
      if (delete $pri{$construct_as[$i][1]}) {
        push(@pri_index, $i);
      }
      last unless keys %pri; # short circuit (Johnny Five Is Alive!)
    }
  }

  # no need to do an if, it'll be empty if @pri_index is empty anyway

  my %pri_vals = map { ($_ => $copy[$_]) } @pri_index;

  my @const_rows;

  do { # no need to check anything at the front, we always want the first row

    my %const;

    foreach my $this_as (@construct_as) {
      $const{$this_as->[0]||''}{$this_as->[1]} = shift(@copy);
    }

    push(@const_rows, \%const);

  } until ( # no pri_index => no collapse => drop straight out
      !@pri_index
    or
      do { # get another row, stash it, drop out if different PK

        @copy = $self->cursor->next;
        $self->{stashed_row} = \@copy;

        # last thing in do block, counts as true if anything doesn't match

        # check xor defined first for NULL vs. NOT NULL then if one is
        # defined the other must be so check string equality

        grep {
          (defined $pri_vals{$_} ^ defined $copy[$_])
          || (defined $pri_vals{$_} && ($pri_vals{$_} ne $copy[$_]))
        } @pri_index;
      }
  );

  my $alias = $self->{attrs}{alias};
  my $info = [];

  my %collapse_pos;

  my @const_keys;

  foreach my $const (@const_rows) {
    scalar @const_keys or do {
      @const_keys = sort { length($a) <=> length($b) } keys %$const;
    };
    foreach my $key (@const_keys) {
      if (length $key) {
        my $target = $info;
        my @parts = split(/\./, $key);
        my $cur = '';
        my $data = $const->{$key};
        foreach my $p (@parts) {
          $target = $target->[1]->{$p} ||= [];
          $cur .= ".${p}";
          if ($cur eq ".${key}" && (my @ckey = @{$collapse{$cur}||[]})) {
            # collapsing at this point and on final part
            my $pos = $collapse_pos{$cur};
            CK: foreach my $ck (@ckey) {
              if (!defined $pos->{$ck} || $pos->{$ck} ne $data->{$ck}) {
                $collapse_pos{$cur} = $data;
                delete @collapse_pos{ # clear all positioning for sub-entries
                  grep { m/^\Q${cur}.\E/ } keys %collapse_pos
                };
                push(@$target, []);
                last CK;
              }
            }
          }
          if (exists $collapse{$cur}) {
            $target = $target->[-1];
          }
        }
        $target->[0] = $data;
      } else {
        $info->[0] = $const->{$key};
      }
    }
  }

  return $info;
}

=head2 result_source

=over 4

=item Arguments: $result_source?

=item Return Value: $result_source

=back

An accessor for the primary ResultSource object from which this ResultSet
is derived.

=head2 result_class

=over 4

=item Arguments: $result_class?

=item Return Value: $result_class

=back

An accessor for the class to use when creating row objects. Defaults to
C<< result_source->result_class >> - which in most cases is the name of the
L<"table"|DBIx::Class::Manual::Glossary/"ResultSource"> class.

Note that changing the result_class will also remove any components
that were originally loaded in the source class via
L<DBIx::Class::ResultSource/load_components>. Any overloaded methods
in the original source class will not run.

=cut

sub result_class {
  my ($self, $result_class) = @_;
  if ($result_class) {
    unless (ref $result_class) { # don't fire this for an object
      $self->ensure_class_loaded($result_class);
    }
    $self->_result_class($result_class);
    # THIS LINE WOULD BE A BUG - this accessor specifically exists to
    # permit the user to set result class on one result set only; it only
    # chains if provided to search()
    #$self->{attrs}{result_class} = $result_class if ref $self;
  }
  $self->_result_class;
}

=head2 count

=over 4

=item Arguments: $cond, \%attrs??

=item Return Value: $count

=back

Performs an SQL C<COUNT> with the same query as the resultset was built
with to find the number of elements. Passing arguments is equivalent to
C<< $rs->search ($cond, \%attrs)->count >>

=cut

sub count {
  my $self = shift;
  return $self->search(@_)->count if @_ and defined $_[0];
  return scalar @{ $self->get_cache } if $self->get_cache;

  my $attrs = $self->_resolved_attrs_copy;

  # this is a little optimization - it is faster to do the limit
  # adjustments in software, instead of a subquery
  my $rows = delete $attrs->{rows};
  my $offset = delete $attrs->{offset};

  my $crs;
  if ($self->_has_resolved_attr (qw/collapse group_by/)) {
    $crs = $self->_count_subq_rs ($attrs);
  }
  else {
    $crs = $self->_count_rs ($attrs);
  }
  my $count = $crs->next;

  $count -= $offset if $offset;
  $count = $rows if $rows and $rows < $count;
  $count = 0 if ($count < 0);

  return $count;
}

=head2 count_rs

=over 4

=item Arguments: $cond, \%attrs??

=item Return Value: $count_rs

=back

Same as L</count> but returns a L<DBIx::Class::ResultSetColumn> object.
This can be very handy for subqueries:

  ->search( { amount => $some_rs->count_rs->as_query } )

As with regular resultsets the SQL query will be executed only after
the resultset is accessed via L</next> or L</all>. That would return
the same single value obtainable via L</count>.

=cut

sub count_rs {
  my $self = shift;
  return $self->search(@_)->count_rs if @_;

  # this may look like a lack of abstraction (count() does about the same)
  # but in fact an _rs *must* use a subquery for the limits, as the
  # software based limiting can not be ported if this $rs is to be used
  # in a subquery itself (i.e. ->as_query)
  if ($self->_has_resolved_attr (qw/collapse group_by offset rows/)) {
    return $self->_count_subq_rs;
  }
  else {
    return $self->_count_rs;
  }
}

#
# returns a ResultSetColumn object tied to the count query
#
sub _count_rs {
  my ($self, $attrs) = @_;

  my $rsrc = $self->result_source;
  $attrs ||= $self->_resolved_attrs;

  my $tmp_attrs = { %$attrs };
  # take off any limits, record_filter is cdbi, and no point of ordering nor locking a count
  delete @{$tmp_attrs}{qw/rows offset order_by record_filter for/};

  # overwrite the selector (supplied by the storage)
  $tmp_attrs->{select} = $rsrc->storage->_count_select ($rsrc, $attrs);
  $tmp_attrs->{as} = 'count';
  delete @{$tmp_attrs}{qw/columns/};

  my $tmp_rs = $rsrc->resultset_class->new($rsrc, $tmp_attrs)->get_column ('count');

  return $tmp_rs;
}

#
# same as above but uses a subquery
#
sub _count_subq_rs {
  my ($self, $attrs) = @_;

  my $rsrc = $self->result_source;
  $attrs ||= $self->_resolved_attrs;

  my $sub_attrs = { %$attrs };
  # extra selectors do not go in the subquery and there is no point of ordering it, nor locking it
  delete @{$sub_attrs}{qw/collapse columns as select _prefetch_selector_range order_by for/};

  # if we multi-prefetch we group_by primary keys only as this is what we would
  # get out of the rs via ->next/->all. We *DO WANT* to clobber old group_by regardless
  if ( keys %{$attrs->{collapse}}  ) {
    $sub_attrs->{group_by} = [ map { "$attrs->{alias}.$_" } ($rsrc->_pri_cols) ]
  }

  # Calculate subquery selector
  if (my $g = $sub_attrs->{group_by}) {

    my $sql_maker = $rsrc->storage->sql_maker;

    # necessary as the group_by may refer to aliased functions
    my $sel_index;
    for my $sel (@{$attrs->{select}}) {
      $sel_index->{$sel->{-as}} = $sel
        if (ref $sel eq 'HASH' and $sel->{-as});
    }

    # anything from the original select mentioned on the group-by needs to make it to the inner selector
    # also look for named aggregates referred in the having clause
    # having often contains scalarrefs - thus parse it out entirely
    my @parts = @$g;
    if ($attrs->{having}) {
      local $sql_maker->{having_bind};
      local $sql_maker->{quote_char} = $sql_maker->{quote_char};
      local $sql_maker->{name_sep} = $sql_maker->{name_sep};
      unless (defined $sql_maker->{quote_char} and length $sql_maker->{quote_char}) {
        $sql_maker->{quote_char} = [ "\x00", "\xFF" ];
        # if we don't unset it we screw up retarded but unfortunately working
        # 'MAX(foo.bar)' => { '>', 3 }
        $sql_maker->{name_sep} = '';
      }

      my ($lquote, $rquote, $sep) = map { quotemeta $_ } ($sql_maker->_quote_chars, $sql_maker->name_sep);

      my $sql = $sql_maker->_parse_rs_attrs ({ having => $attrs->{having} });

      # search for both a proper quoted qualified string, for a naive unquoted scalarref
      # and if all fails for an utterly naive quoted scalar-with-function
      while ($sql =~ /
        $rquote $sep $lquote (.+?) $rquote
          |
        [\s,] \w+ \. (\w+) [\s,]
          |
        [\s,] $lquote (.+?) $rquote [\s,]
      /gx) {
        push @parts, ($1 || $2 || $3);  # one of them matched if we got here
      }
    }

    for (@parts) {
      my $colpiece = $sel_index->{$_} || $_;

      # unqualify join-based group_by's. Arcane but possible query
      # also horrible horrible hack to alias a column (not a func.)
      # (probably need to introduce SQLA syntax)
      if ($colpiece =~ /\./ && $colpiece !~ /^$attrs->{alias}\./) {
        my $as = $colpiece;
        $as =~ s/\./__/;
        $colpiece = \ sprintf ('%s AS %s', map { $sql_maker->_quote ($_) } ($colpiece, $as) );
      }
      push @{$sub_attrs->{select}}, $colpiece;
    }
  }
  else {
    my @pcols = map { "$attrs->{alias}.$_" } ($rsrc->primary_columns);
    $sub_attrs->{select} = @pcols ? \@pcols : [ 1 ];
  }

  return $rsrc->resultset_class
               ->new ($rsrc, $sub_attrs)
                ->as_subselect_rs
                 ->search ({}, { columns => { count => $rsrc->storage->_count_select ($rsrc, $attrs) } })
                  ->get_column ('count');
}

sub _bool {
  return 1;
}

=head2 count_literal

=over 4

=item Arguments: $sql_fragment, @bind_values

=item Return Value: $count

=back

Counts the results in a literal query. Equivalent to calling L</search_literal>
with the passed arguments, then L</count>.

=cut

sub count_literal { shift->search_literal(@_)->count; }

=head2 all

=over 4

=item Arguments: none

=item Return Value: @objects

=back

Returns all elements in the resultset.

=cut

sub all {
  my $self = shift;
  if(@_) {
      $self->throw_exception("all() doesn't take any arguments, you probably wanted ->search(...)->all()");
  }

  return @{ $self->get_cache } if $self->get_cache;

  my @obj;

  if (keys %{$self->_resolved_attrs->{collapse}}) {
    # Using $self->cursor->all is really just an optimisation.
    # If we're collapsing has_many prefetches it probably makes
    # very little difference, and this is cleaner than hacking
    # _construct_object to survive the approach
    $self->cursor->reset;
    my @row = $self->cursor->next;
    while (@row) {
      push(@obj, $self->_construct_object(@row));
      @row = (exists $self->{stashed_row}
               ? @{delete $self->{stashed_row}}
               : $self->cursor->next);
    }
  } else {
    @obj = map { $self->_construct_object(@$_) } $self->cursor->all;
  }

  $self->set_cache(\@obj) if $self->{attrs}{cache};

  return @obj;
}

=head2 reset

=over 4

=item Arguments: none

=item Return Value: $self

=back

Resets the resultset's cursor, so you can iterate through the elements again.
Implicitly resets the storage cursor, so a subsequent L</next> will trigger
another query.

=cut

sub reset {
  my ($self) = @_;
  delete $self->{_attrs} if exists $self->{_attrs};
  $self->{all_cache_position} = 0;
  $self->cursor->reset;
  return $self;
}

=head2 first

=over 4

=item Arguments: none

=item Return Value: $object | undef

=back

Resets the resultset and returns an object for the first result (or C<undef>
if the resultset is empty).

=cut

sub first {
  return $_[0]->reset->next;
}


# _rs_update_delete
#
# Determines whether and what type of subquery is required for the $rs operation.
# If grouping is necessary either supplies its own, or verifies the current one
# After all is done delegates to the proper storage method.

sub _rs_update_delete {
  my ($self, $op, $values) = @_;

  my $rsrc = $self->result_source;

  my $needs_group_by_subq = $self->_has_resolved_attr (qw/collapse group_by -join/);
  my $needs_subq = $needs_group_by_subq || $self->_has_resolved_attr(qw/rows offset/);

  if ($needs_group_by_subq or $needs_subq) {

    # make a new $rs selecting only the PKs (that's all we really need)
    my $attrs = $self->_resolved_attrs_copy;


    delete $attrs->{$_} for qw/collapse _collapse_order_by select _prefetch_selector_range as/;
    $attrs->{columns} = [ map { "$attrs->{alias}.$_" } ($self->result_source->_pri_cols) ];

    if ($needs_group_by_subq) {
      # make sure no group_by was supplied, or if there is one - make sure it matches
      # the columns compiled above perfectly. Anything else can not be sanely executed
      # on most databases so croak right then and there

      if (my $g = $attrs->{group_by}) {
        my @current_group_by = map
          { $_ =~ /\./ ? $_ : "$attrs->{alias}.$_" }
          @$g
        ;

        if (
          join ("\x00", sort @current_group_by)
            ne
          join ("\x00", sort @{$attrs->{columns}} )
        ) {
          $self->throw_exception (
            "You have just attempted a $op operation on a resultset which does group_by"
            . ' on columns other than the primary keys, while DBIC internally needs to retrieve'
            . ' the primary keys in a subselect. All sane RDBMS engines do not support this'
            . ' kind of queries. Please retry the operation with a modified group_by or'
            . ' without using one at all.'
          );
        }
      }
      else {
        $attrs->{group_by} = $attrs->{columns};
      }
    }

    my $subrs = (ref $self)->new($rsrc, $attrs);
    return $self->result_source->storage->_subq_update_delete($subrs, $op, $values);
  }
  else {
    # Most databases do not allow aliasing of tables in UPDATE/DELETE. Thus
    # a condition containing 'me' or other table prefixes will not work
    # at all. What this code tries to do (badly) is to generate a condition
    # with the qualifiers removed, by exploiting the quote mechanism of sqla
    #
    # this is atrocious and should be replaced by normal sqla introspection
    # one sunny day
    my ($sql, @bind) = do {
      my $sqla = $rsrc->storage->sql_maker;
      local $sqla->{_dequalify_idents} = 1;
      $sqla->_recurse_where($self->{cond});
    } if $self->{cond};

    return $rsrc->storage->$op(
      $rsrc,
      $op eq 'update' ? $values : (),
      $self->{cond} ? \[$sql, @bind] : (),
    );
  }
}

=head2 update

=over 4

=item Arguments: \%values

=item Return Value: $storage_rv

=back

Sets the specified columns in the resultset to the supplied values in a
single query. Note that this will not run any accessor/set_column/update
triggers, nor will it update any row object instances derived from this
resultset (this includes the contents of the L<resultset cache|/set_cache>
if any). See L</update_all> if you need to execute any on-update
triggers or cascades defined either by you or a
L<result component|DBIx::Class::Manual::Component/WHAT_IS_A_COMPONENT>.

The return value is a pass through of what the underlying
storage backend returned, and may vary. See L<DBI/execute> for the most
common case.

=head3 CAVEAT

Note that L</update> does not process/deflate any of the values passed in.
This is unlike the corresponding L<DBIx::Class::Row/update>. The user must
ensure manually that any value passed to this method will stringify to
something the RDBMS knows how to deal with. A notable example is the
handling of L<DateTime> objects, for more info see:
L<DBIx::Class::Manual::Cookbook/Formatting_DateTime_objects_in_queries>.

=cut

sub update {
  my ($self, $values) = @_;
  $self->throw_exception('Values for update must be a hash')
    unless ref $values eq 'HASH';

  return $self->_rs_update_delete ('update', $values);
}

=head2 update_all

=over 4

=item Arguments: \%values

=item Return Value: 1

=back

Fetches all objects and updates them one at a time via
L<DBIx::Class::Row/update>. Note that C<update_all> will run DBIC defined
triggers, while L</update> will not.

=cut

sub update_all {
  my ($self, $values) = @_;
  $self->throw_exception('Values for update_all must be a hash')
    unless ref $values eq 'HASH';

  my $guard = $self->result_source->schema->txn_scope_guard;
  $_->update({%$values}) for $self->all;  # shallow copy - update will mangle it
  $guard->commit;
  return 1;
}

=head2 delete

=over 4

=item Arguments: none

=item Return Value: $storage_rv

=back

Deletes the rows matching this resultset in a single query. Note that this
will not run any delete triggers, nor will it alter the
L<in_storage|DBIx::Class::Row/in_storage> status of any row object instances
derived from this resultset (this includes the contents of the
L<resultset cache|/set_cache> if any). See L</delete_all> if you need to
execute any on-delete triggers or cascades defined either by you or a
L<result component|DBIx::Class::Manual::Component/WHAT_IS_A_COMPONENT>.

The return value is a pass through of what the underlying storage backend
returned, and may vary. See L<DBI/execute> for the most common case.

=cut

sub delete {
  my $self = shift;
  $self->throw_exception('delete does not accept any arguments')
    if @_;

  return $self->_rs_update_delete ('delete');
}

=head2 delete_all

=over 4

=item Arguments: none

=item Return Value: 1

=back

Fetches all objects and deletes them one at a time via
L<DBIx::Class::Row/delete>. Note that C<delete_all> will run DBIC defined
triggers, while L</delete> will not.

=cut

sub delete_all {
  my $self = shift;
  $self->throw_exception('delete_all does not accept any arguments')
    if @_;

  my $guard = $self->result_source->schema->txn_scope_guard;
  $_->delete for $self->all;
  $guard->commit;
  return 1;
}

=head2 populate

=over 4

=item Arguments: \@data;

=back

Accepts either an arrayref of hashrefs or alternatively an arrayref of arrayrefs.
For the arrayref of hashrefs style each hashref should be a structure suitable
for submitting to a $resultset->create(...) method.

In void context, C<insert_bulk> in L<DBIx::Class::Storage::DBI> is used
to insert the data, as this is a faster method.

Otherwise, each set of data is inserted into the database using
L<DBIx::Class::ResultSet/create>, and the resulting objects are
accumulated into an array. The array itself, or an array reference
is returned depending on scalar or list context.

Example:  Assuming an Artist Class that has many CDs Classes relating:

  my $Artist_rs = $schema->resultset("Artist");

  ## Void Context Example
  $Artist_rs->populate([
     { artistid => 4, name => 'Manufactured Crap', cds => [
        { title => 'My First CD', year => 2006 },
        { title => 'Yet More Tweeny-Pop crap', year => 2007 },
      ],
     },
     { artistid => 5, name => 'Angsty-Whiny Girl', cds => [
        { title => 'My parents sold me to a record company', year => 2005 },
        { title => 'Why Am I So Ugly?', year => 2006 },
        { title => 'I Got Surgery and am now Popular', year => 2007 }
      ],
     },
  ]);

  ## Array Context Example
  my ($ArtistOne, $ArtistTwo, $ArtistThree) = $Artist_rs->populate([
    { name => "Artist One"},
    { name => "Artist Two"},
    { name => "Artist Three", cds=> [
    { title => "First CD", year => 2007},
    { title => "Second CD", year => 2008},
  ]}
  ]);

  print $ArtistOne->name; ## response is 'Artist One'
  print $ArtistThree->cds->count ## reponse is '2'

For the arrayref of arrayrefs style,  the first element should be a list of the
fieldsnames to which the remaining elements are rows being inserted.  For
example:

  $Arstist_rs->populate([
    [qw/artistid name/],
    [100, 'A Formally Unknown Singer'],
    [101, 'A singer that jumped the shark two albums ago'],
    [102, 'An actually cool singer'],
  ]);

Please note an important effect on your data when choosing between void and
wantarray context. Since void context goes straight to C<insert_bulk> in
L<DBIx::Class::Storage::DBI> this will skip any component that is overriding
C<insert>.  So if you are using something like L<DBIx-Class-UUIDColumns> to
create primary keys for you, you will find that your PKs are empty.  In this
case you will have to use the wantarray context in order to create those
values.

=cut

sub populate {
  my $self = shift;

  # cruft placed in standalone method
  my $data = $self->_normalize_populate_args(@_);

  return unless @$data;

  if(defined wantarray) {
    my @created;
    foreach my $item (@$data) {
      push(@created, $self->create($item));
    }
    return wantarray ? @created : \@created;
  } 
  else {
    my $first = $data->[0];

    # if a column is a registered relationship, and is a non-blessed hash/array, consider
    # it relationship data
    my (@rels, @columns);
    my $rsrc = $self->result_source;
    my $rels = { map { $_ => $rsrc->relationship_info($_) } $rsrc->relationships };
    for (keys %$first) {
      my $ref = ref $first->{$_};
      $rels->{$_} && ($ref eq 'ARRAY' or $ref eq 'HASH')
        ? push @rels, $_
        : push @columns, $_
      ;
    }

    my @pks = $rsrc->primary_columns;

    ## do the belongs_to relationships
    foreach my $index (0..$#$data) {

      # delegate to create() for any dataset without primary keys with specified relationships
      if (grep { !defined $data->[$index]->{$_} } @pks ) {
        for my $r (@rels) {
          if (grep { ref $data->[$index]{$r} eq $_ } qw/HASH ARRAY/) {  # a related set must be a HASH or AoH
            my @ret = $self->populate($data);
            return;
          }
        }
      }

      foreach my $rel (@rels) {
        next unless ref $data->[$index]->{$rel} eq "HASH";
        my $result = $self->related_resultset($rel)->create($data->[$index]->{$rel});
        my ($reverse_relname, $reverse_relinfo) = %{$rsrc->reverse_relationship_info($rel)};
        my $related = $result->result_source->_resolve_condition(
          $reverse_relinfo->{cond},
          $self,
          $result,
          $rel,
        );

        delete $data->[$index]->{$rel};
        $data->[$index] = {%{$data->[$index]}, %$related};

        push @columns, keys %$related if $index == 0;
      }
    }

    ## inherit the data locked in the conditions of the resultset
    my ($rs_data) = $self->_merge_with_rscond({});
    delete @{$rs_data}{@columns};
    my @inherit_cols = keys %$rs_data;
    my @inherit_data = values %$rs_data;

    ## do bulk insert on current row
    $rsrc->storage->insert_bulk(
      $rsrc,
      [@columns, @inherit_cols],
      [ map { [ @$_{@columns}, @inherit_data ] } @$data ],
    );

    ## do the has_many relationships
    foreach my $item (@$data) {

      my $main_row;

      foreach my $rel (@rels) {
        next unless ref $item->{$rel} eq "ARRAY" && @{ $item->{$rel} };

        $main_row ||= $self->new_result({map { $_ => $item->{$_} } @pks});

        my $child = $main_row->$rel;

        my $related = $child->result_source->_resolve_condition(
          $rels->{$rel}{cond},
          $child,
          $main_row,
          $rel,
        );

        my @rows_to_add = ref $item->{$rel} eq 'ARRAY' ? @{$item->{$rel}} : ($item->{$rel});
        my @populate = map { {%$_, %$related} } @rows_to_add;

        $child->populate( \@populate );
      }
    }
  }
}


# populate() argumnets went over several incarnations
# What we ultimately support is AoH
sub _normalize_populate_args {
  my ($self, $arg) = @_;

  if (ref $arg eq 'ARRAY') {
    if (!@$arg) {
      return [];
    }
    elsif (ref $arg->[0] eq 'HASH') {
      return $arg;
    }
    elsif (ref $arg->[0] eq 'ARRAY') {
      my @ret;
      my @colnames = @{$arg->[0]};
      foreach my $values (@{$arg}[1 .. $#$arg]) {
        push @ret, { map { $colnames[$_] => $values->[$_] } (0 .. $#colnames) };
      }
      return \@ret;
    }
  }

  $self->throw_exception('Populate expects an arrayref of hashrefs or arrayref of arrayrefs');
}

=head2 pager

=over 4

=item Arguments: none

=item Return Value: $pager

=back

Return Value a L<Data::Page> object for the current resultset. Only makes
sense for queries with a C<page> attribute.

To get the full count of entries for a paged resultset, call
C<total_entries> on the L<Data::Page> object.

=cut

sub pager {
  my ($self) = @_;

  return $self->{pager} if $self->{pager};

  my $attrs = $self->{attrs};
  if (!defined $attrs->{page}) {
    $self->throw_exception("Can't create pager for non-paged rs");
  }
  elsif ($attrs->{page} <= 0) {
    $self->throw_exception('Invalid page number (page-numbers are 1-based)');
  }
  $attrs->{rows} ||= 10;

  # throw away the paging flags and re-run the count (possibly
  # with a subselect) to get the real total count
  my $count_attrs = { %$attrs };
  delete $count_attrs->{$_} for qw/rows offset page pager/;

  my $total_rs = (ref $self)->new($self->result_source, $count_attrs);

  require DBIx::Class::ResultSet::Pager;
  return $self->{pager} = DBIx::Class::ResultSet::Pager->new(
    sub { $total_rs->count },  #lazy-get the total
    $attrs->{rows},
    $self->{attrs}{page},
  );
}

=head2 page

=over 4

=item Arguments: $page_number

=item Return Value: $rs

=back

Returns a resultset for the $page_number page of the resultset on which page
is called, where each page contains a number of rows equal to the 'rows'
attribute set on the resultset (10 by default).

=cut

sub page {
  my ($self, $page) = @_;
  return (ref $self)->new($self->result_source, { %{$self->{attrs}}, page => $page });
}

=head2 new_result

=over 4

=item Arguments: \%vals

=item Return Value: $rowobject

=back

Creates a new row object in the resultset's result class and returns
it. The row is not inserted into the database at this point, call
L<DBIx::Class::Row/insert> to do that. Calling L<DBIx::Class::Row/in_storage>
will tell you whether the row object has been inserted or not.

Passes the hashref of input on to L<DBIx::Class::Row/new>.

=cut

sub new_result {
  my ($self, $values) = @_;
  $self->throw_exception( "new_result needs a hash" )
    unless (ref $values eq 'HASH');

  my ($merged_cond, $cols_from_relations) = $self->_merge_with_rscond($values);

  my %new = (
    %$merged_cond,
    @$cols_from_relations
      ? (-cols_from_relations => $cols_from_relations)
      : (),
    -result_source => $self->result_source, # DO NOT REMOVE THIS, REQUIRED
  );

  return $self->result_class->new(\%new);
}

# _merge_with_rscond
#
# Takes a simple hash of K/V data and returns its copy merged with the
# condition already present on the resultset. Additionally returns an
# arrayref of value/condition names, which were inferred from related
# objects (this is needed for in-memory related objects)
sub _merge_with_rscond {
  my ($self, $data) = @_;

  my (%new_data, @cols_from_relations);

  my $alias = $self->{attrs}{alias};

  if (! defined $self->{cond}) {
    # just massage $data below
  }
  elsif ($self->{cond} eq $DBIx::Class::ResultSource::UNRESOLVABLE_CONDITION) {
    %new_data = %{ $self->{attrs}{related_objects} || {} };  # nothing might have been inserted yet
    @cols_from_relations = keys %new_data;
  }
  elsif (ref $self->{cond} ne 'HASH') {
    $self->throw_exception(
      "Can't abstract implicit construct, resultset condition not a hash"
    );
  }
  else {
    # precendence must be given to passed values over values inherited from
    # the cond, so the order here is important.
    my $collapsed_cond = $self->_collapse_cond($self->{cond});
    my %implied = %{$self->_remove_alias($collapsed_cond, $alias)};

    while ( my($col, $value) = each %implied ) {
      my $vref = ref $value;
      if (
        $vref eq 'HASH'
          and
        keys(%$value) == 1
          and
        (keys %$value)[0] eq '='
      ) {
        $new_data{$col} = $value->{'='};
      }
      elsif( !$vref or $vref eq 'SCALAR' or blessed($value) ) {
        $new_data{$col} = $value;
      }
    }
  }

  %new_data = (
    %new_data,
    %{ $self->_remove_alias($data, $alias) },
  );

  return (\%new_data, \@cols_from_relations);
}

# _has_resolved_attr
#
# determines if the resultset defines at least one
# of the attributes supplied
#
# used to determine if a subquery is neccessary
#
# supports some virtual attributes:
#   -join
#     This will scan for any joins being present on the resultset.
#     It is not a mere key-search but a deep inspection of {from}
#

sub _has_resolved_attr {
  my ($self, @attr_names) = @_;

  my $attrs = $self->_resolved_attrs;

  my %extra_checks;

  for my $n (@attr_names) {
    if (grep { $n eq $_ } (qw/-join/) ) {
      $extra_checks{$n}++;
      next;
    }

    my $attr =  $attrs->{$n};

    next if not defined $attr;

    if (ref $attr eq 'HASH') {
      return 1 if keys %$attr;
    }
    elsif (ref $attr eq 'ARRAY') {
      return 1 if @$attr;
    }
    else {
      return 1 if $attr;
    }
  }

  # a resolved join is expressed as a multi-level from
  return 1 if (
    $extra_checks{-join}
      and
    ref $attrs->{from} eq 'ARRAY'
      and
    @{$attrs->{from}} > 1
  );

  return 0;
}

# _collapse_cond
#
# Recursively collapse the condition.

sub _collapse_cond {
  my ($self, $cond, $collapsed) = @_;

  $collapsed ||= {};

  if (ref $cond eq 'ARRAY') {
    foreach my $subcond (@$cond) {
      next unless ref $subcond;  # -or
      $collapsed = $self->_collapse_cond($subcond, $collapsed);
    }
  }
  elsif (ref $cond eq 'HASH') {
    if (keys %$cond and (keys %$cond)[0] eq '-and') {
      foreach my $subcond (@{$cond->{-and}}) {
        $collapsed = $self->_collapse_cond($subcond, $collapsed);
      }
    }
    else {
      foreach my $col (keys %$cond) {
        my $value = $cond->{$col};
        $collapsed->{$col} = $value;
      }
    }
  }

  return $collapsed;
}

# _remove_alias
#
# Remove the specified alias from the specified query hash. A copy is made so
# the original query is not modified.

sub _remove_alias {
  my ($self, $query, $alias) = @_;

  my %orig = %{ $query || {} };
  my %unaliased;

  foreach my $key (keys %orig) {
    if ($key !~ /\./) {
      $unaliased{$key} = $orig{$key};
      next;
    }
    $unaliased{$1} = $orig{$key}
      if $key =~ m/^(?:\Q$alias\E\.)?([^.]+)$/;
  }

  return \%unaliased;
}

=head2 as_query

=over 4

=item Arguments: none

=item Return Value: \[ $sql, @bind ]

=back

Returns the SQL query and bind vars associated with the invocant.

This is generally used as the RHS for a subquery.

=cut

sub as_query {
  my $self = shift;

  my $attrs = $self->_resolved_attrs_copy;

  # For future use:
  #
  # in list ctx:
  # my ($sql, \@bind, \%dbi_bind_attrs) = _select_args_to_query (...)
  # $sql also has no wrapping parenthesis in list ctx
  #
  my $sqlbind = $self->result_source->storage
    ->_select_args_to_query ($attrs->{from}, $attrs->{select}, $attrs->{where}, $attrs);

  return $sqlbind;
}

=head2 find_or_new

=over 4

=item Arguments: \%vals, \%attrs?

=item Return Value: $rowobject

=back

  my $artist = $schema->resultset('Artist')->find_or_new(
    { artist => 'fred' }, { key => 'artists' });

  $cd->cd_to_producer->find_or_new({ producer => $producer },
                                   { key => 'primary });

Find an existing record from this resultset using L</find>. if none exists,
instantiate a new result object and return it. The object will not be saved
into your storage until you call L<DBIx::Class::Row/insert> on it.

You most likely want this method when looking for existing rows using a unique
constraint that is not the primary key, or looking for related rows.

If you want objects to be saved immediately, use L</find_or_create> instead.

B<Note>: Make sure to read the documentation of L</find> and understand the
significance of the C<key> attribute, as its lack may skew your search, and
subsequently result in spurious new objects.

B<Note>: Take care when using C<find_or_new> with a table having
columns with default values that you intend to be automatically
supplied by the database (e.g. an auto_increment primary key column).
In normal usage, the value of such columns should NOT be included at
all in the call to C<find_or_new>, even when set to C<undef>.

=cut

sub find_or_new {
  my $self     = shift;
  my $attrs    = (@_ > 1 && ref $_[$#_] eq 'HASH' ? pop(@_) : {});
  my $hash     = ref $_[0] eq 'HASH' ? shift : {@_};
  if (keys %$hash and my $row = $self->find($hash, $attrs) ) {
    return $row;
  }
  return $self->new_result($hash);
}

=head2 create

=over 4

=item Arguments: \%vals

=item Return Value: a L<DBIx::Class::Row> $object

=back

Attempt to create a single new row or a row with multiple related rows
in the table represented by the resultset (and related tables). This
will not check for duplicate rows before inserting, use
L</find_or_create> to do that.

To create one row for this resultset, pass a hashref of key/value
pairs representing the columns of the table and the values you wish to
store. If the appropriate relationships are set up, foreign key fields
can also be passed an object representing the foreign row, and the
value will be set to its primary key.

To create related objects, pass a hashref of related-object column values
B<keyed on the relationship name>. If the relationship is of type C<multi>
(L<DBIx::Class::Relationship/has_many>) - pass an arrayref of hashrefs.
The process will correctly identify columns holding foreign keys, and will
transparently populate them from the keys of the corresponding relation.
This can be applied recursively, and will work correctly for a structure
with an arbitrary depth and width, as long as the relationships actually
exists and the correct column data has been supplied.


Instead of hashrefs of plain related data (key/value pairs), you may
also pass new or inserted objects. New objects (not inserted yet, see
L</new>), will be inserted into their appropriate tables.

Effectively a shortcut for C<< ->new_result(\%vals)->insert >>.

Example of creating a new row.

  $person_rs->create({
    name=>"Some Person",
    email=>"somebody@someplace.com"
  });

Example of creating a new row and also creating rows in a related C<has_many>
or C<has_one> resultset.  Note Arrayref.

  $artist_rs->create(
     { artistid => 4, name => 'Manufactured Crap', cds => [
        { title => 'My First CD', year => 2006 },
        { title => 'Yet More Tweeny-Pop crap', year => 2007 },
      ],
     },
  );

Example of creating a new row and also creating a row in a related
C<belongs_to> resultset. Note Hashref.

  $cd_rs->create({
    title=>"Music for Silly Walks",
    year=>2000,
    artist => {
      name=>"Silly Musician",
    }
  });

=over

=item WARNING

When subclassing ResultSet never attempt to override this method. Since
it is a simple shortcut for C<< $self->new_result($attrs)->insert >>, a
lot of the internals simply never call it, so your override will be
bypassed more often than not. Override either L<new|DBIx::Class::Row/new>
or L<insert|DBIx::Class::Row/insert> depending on how early in the
L</create> process you need to intervene.

=back

=cut

sub create {
  my ($self, $attrs) = @_;
  $self->throw_exception( "create needs a hashref" )
    unless ref $attrs eq 'HASH';
  return $self->new_result($attrs)->insert;
}

=head2 find_or_create

=over 4

=item Arguments: \%vals, \%attrs?

=item Return Value: $rowobject

=back

  $cd->cd_to_producer->find_or_create({ producer => $producer },
                                      { key => 'primary' });

Tries to find a record based on its primary key or unique constraints; if none
is found, creates one and returns that instead.

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
    { key => 'cd_artist_title' }
  );

B<Note>: Make sure to read the documentation of L</find> and understand the
significance of the C<key> attribute, as its lack may skew your search, and
subsequently result in spurious row creation.

B<Note>: Because find_or_create() reads from the database and then
possibly inserts based on the result, this method is subject to a race
condition. Another process could create a record in the table after
the find has completed and before the create has started. To avoid
this problem, use find_or_create() inside a transaction.

B<Note>: Take care when using C<find_or_create> with a table having
columns with default values that you intend to be automatically
supplied by the database (e.g. an auto_increment primary key column).
In normal usage, the value of such columns should NOT be included at
all in the call to C<find_or_create>, even when set to C<undef>.

See also L</find> and L</update_or_create>. For information on how to declare
unique constraints, see L<DBIx::Class::ResultSource/add_unique_constraint>.

=cut

sub find_or_create {
  my $self     = shift;
  my $attrs    = (@_ > 1 && ref $_[$#_] eq 'HASH' ? pop(@_) : {});
  my $hash     = ref $_[0] eq 'HASH' ? shift : {@_};
  if (keys %$hash and my $row = $self->find($hash, $attrs) ) {
    return $row;
  }
  return $self->create($hash);
}

=head2 update_or_create

=over 4

=item Arguments: \%col_values, { key => $unique_constraint }?

=item Return Value: $row_object

=back

  $resultset->update_or_create({ col => $val, ... });

Like L</find_or_create>, but if a row is found it is immediately updated via
C<< $found_row->update (\%col_values) >>.


Takes an optional C<key> attribute to search on a specific unique constraint.
For example:

  # In your application
  my $cd = $schema->resultset('CD')->update_or_create(
    {
      artist => 'Massive Attack',
      title  => 'Mezzanine',
      year   => 1998,
    },
    { key => 'cd_artist_title' }
  );

  $cd->cd_to_producer->update_or_create({
    producer => $producer,
    name => 'harry',
  }, {
    key => 'primary',
  });

B<Note>: Make sure to read the documentation of L</find> and understand the
significance of the C<key> attribute, as its lack may skew your search, and
subsequently result in spurious row creation.

B<Note>: Take care when using C<update_or_create> with a table having
columns with default values that you intend to be automatically
supplied by the database (e.g. an auto_increment primary key column).
In normal usage, the value of such columns should NOT be included at
all in the call to C<update_or_create>, even when set to C<undef>.

See also L</find> and L</find_or_create>. For information on how to declare
unique constraints, see L<DBIx::Class::ResultSource/add_unique_constraint>.

=cut

sub update_or_create {
  my $self = shift;
  my $attrs = (@_ > 1 && ref $_[$#_] eq 'HASH' ? pop(@_) : {});
  my $cond = ref $_[0] eq 'HASH' ? shift : {@_};

  my $row = $self->find($cond, $attrs);
  if (defined $row) {
    $row->update($cond);
    return $row;
  }

  return $self->create($cond);
}

=head2 update_or_new

=over 4

=item Arguments: \%col_values, { key => $unique_constraint }?

=item Return Value: $rowobject

=back

  $resultset->update_or_new({ col => $val, ... });

Like L</find_or_new> but if a row is found it is immediately updated via
C<< $found_row->update (\%col_values) >>.

For example:

  # In your application
  my $cd = $schema->resultset('CD')->update_or_new(
    {
      artist => 'Massive Attack',
      title  => 'Mezzanine',
      year   => 1998,
    },
    { key => 'cd_artist_title' }
  );

  if ($cd->in_storage) {
      # the cd was updated
  }
  else {
      # the cd is not yet in the database, let's insert it
      $cd->insert;
  }

B<Note>: Make sure to read the documentation of L</find> and understand the
significance of the C<key> attribute, as its lack may skew your search, and
subsequently result in spurious new objects.

B<Note>: Take care when using C<update_or_new> with a table having
columns with default values that you intend to be automatically
supplied by the database (e.g. an auto_increment primary key column).
In normal usage, the value of such columns should NOT be included at
all in the call to C<update_or_new>, even when set to C<undef>.

See also L</find>, L</find_or_create> and L</find_or_new>. 

=cut

sub update_or_new {
    my $self  = shift;
    my $attrs = ( @_ > 1 && ref $_[$#_] eq 'HASH' ? pop(@_) : {} );
    my $cond  = ref $_[0] eq 'HASH' ? shift : {@_};

    my $row = $self->find( $cond, $attrs );
    if ( defined $row ) {
        $row->update($cond);
        return $row;
    }

    return $self->new_result($cond);
}

=head2 get_cache

=over 4

=item Arguments: none

=item Return Value: \@cache_objects | undef

=back

Gets the contents of the cache for the resultset, if the cache is set.

The cache is populated either by using the L</prefetch> attribute to
L</search> or by calling L</set_cache>.

=cut

sub get_cache {
  shift->{all_cache};
}

=head2 set_cache

=over 4

=item Arguments: \@cache_objects

=item Return Value: \@cache_objects

=back

Sets the contents of the cache for the resultset. Expects an arrayref
of objects of the same class as those produced by the resultset. Note that
if the cache is set the resultset will return the cached objects rather
than re-querying the database even if the cache attr is not set.

The contents of the cache can also be populated by using the
L</prefetch> attribute to L</search>.

=cut

sub set_cache {
  my ( $self, $data ) = @_;
  $self->throw_exception("set_cache requires an arrayref")
      if defined($data) && (ref $data ne 'ARRAY');
  $self->{all_cache} = $data;
}

=head2 clear_cache

=over 4

=item Arguments: none

=item Return Value: undef

=back

Clears the cache for the resultset.

=cut

sub clear_cache {
  shift->set_cache(undef);
}

=head2 is_paged

=over 4

=item Arguments: none

=item Return Value: true, if the resultset has been paginated

=back

=cut

sub is_paged {
  my ($self) = @_;
  return !!$self->{attrs}{page};
}

=head2 is_ordered

=over 4

=item Arguments: none

=item Return Value: true, if the resultset has been ordered with C<order_by>.

=back

=cut

sub is_ordered {
  my ($self) = @_;
  return scalar $self->result_source->storage->_extract_order_criteria($self->{attrs}{order_by});
}

=head2 related_resultset

=over 4

=item Arguments: $relationship_name

=item Return Value: $resultset

=back

Returns a related resultset for the supplied relationship name.

  $artist_rs = $schema->resultset('CD')->related_resultset('Artist');

=cut

sub related_resultset {
  my ($self, $rel) = @_;

  $self->{related_resultsets} ||= {};
  return $self->{related_resultsets}{$rel} ||= do {
    my $rsrc = $self->result_source;
    my $rel_info = $rsrc->relationship_info($rel);

    $self->throw_exception(
      "search_related: result source '" . $rsrc->source_name .
        "' has no such relationship $rel")
      unless $rel_info;

    my $attrs = $self->_chain_relationship($rel);

    my $join_count = $attrs->{seen_join}{$rel};

    my $alias = $self->result_source->storage
        ->relname_to_table_alias($rel, $join_count);

    # since this is search_related, and we already slid the select window inwards
    # (the select/as attrs were deleted in the beginning), we need to flip all
    # left joins to inner, so we get the expected results
    # read the comment on top of the actual function to see what this does
    $attrs->{from} = $rsrc->schema->storage->_inner_join_to_node ($attrs->{from}, $alias);


    #XXX - temp fix for result_class bug. There likely is a more elegant fix -groditi
    delete @{$attrs}{qw(result_class alias)};

    my $new_cache;

    if (my $cache = $self->get_cache) {
      if ($cache->[0] && $cache->[0]->related_resultset($rel)->get_cache) {
        $new_cache = [ map { @{$_->related_resultset($rel)->get_cache} }
                        @$cache ];
      }
    }

    my $rel_source = $rsrc->related_source($rel);

    my $new = do {

      # The reason we do this now instead of passing the alias to the
      # search_rs below is that if you wrap/overload resultset on the
      # source you need to know what alias it's -going- to have for things
      # to work sanely (e.g. RestrictWithObject wants to be able to add
      # extra query restrictions, and these may need to be $alias.)

      my $rel_attrs = $rel_source->resultset_attributes;
      local $rel_attrs->{alias} = $alias;

      $rel_source->resultset
                 ->search_rs(
                     undef, {
                       %$attrs,
                       where => $attrs->{where},
                   });
    };
    $new->set_cache($new_cache) if $new_cache;
    $new;
  };
}

=head2 current_source_alias

=over 4

=item Arguments: none

=item Return Value: $source_alias

=back

Returns the current table alias for the result source this resultset is built
on, that will be used in the SQL query. Usually it is C<me>.

Currently the source alias that refers to the result set returned by a
L</search>/L</find> family method depends on how you got to the resultset: it's
C<me> by default, but eg. L</search_related> aliases it to the related result
source name (and keeps C<me> referring to the original result set). The long
term goal is to make L<DBIx::Class> always alias the current resultset as C<me>
(and make this method unnecessary).

Thus it's currently necessary to use this method in predefined queries (see
L<DBIx::Class::Manual::Cookbook/Predefined searches>) when referring to the
source alias of the current result set:

  # in a result set class
  sub modified_by {
    my ($self, $user) = @_;

    my $me = $self->current_source_alias;

    return $self->search(
      "$me.modified" => $user->id,
    );
  }

=cut

sub current_source_alias {
  my ($self) = @_;

  return ($self->{attrs} || {})->{alias} || 'me';
}

=head2 as_subselect_rs

=over 4

=item Arguments: none

=item Return Value: $resultset

=back

Act as a barrier to SQL symbols.  The resultset provided will be made into a
"virtual view" by including it as a subquery within the from clause.  From this
point on, any joined tables are inaccessible to ->search on the resultset (as if
it were simply where-filtered without joins).  For example:

 my $rs = $schema->resultset('Bar')->search({'x.name' => 'abc'},{ join => 'x' });

 # 'x' now pollutes the query namespace

 # So the following works as expected
 my $ok_rs = $rs->search({'x.other' => 1});

 # But this doesn't: instead of finding a 'Bar' related to two x rows (abc and
 # def) we look for one row with contradictory terms and join in another table
 # (aliased 'x_2') which we never use
 my $broken_rs = $rs->search({'x.name' => 'def'});

 my $rs2 = $rs->as_subselect_rs;

 # doesn't work - 'x' is no longer accessible in $rs2, having been sealed away
 my $not_joined_rs = $rs2->search({'x.other' => 1});

 # works as expected: finds a 'table' row related to two x rows (abc and def)
 my $correctly_joined_rs = $rs2->search({'x.name' => 'def'});

Another example of when one might use this would be to select a subset of
columns in a group by clause:

 my $rs = $schema->resultset('Bar')->search(undef, {
   group_by => [qw{ id foo_id baz_id }],
 })->as_subselect_rs->search(undef, {
   columns => [qw{ id foo_id }]
 });

In the above example normally columns would have to be equal to the group by,
but because we isolated the group by into a subselect the above works.

=cut

sub as_subselect_rs {
  my $self = shift;

  my $attrs = $self->_resolved_attrs;

  my $fresh_rs = (ref $self)->new (
    $self->result_source
  );

  # these pieces will be locked in the subquery
  delete $fresh_rs->{cond};
  delete @{$fresh_rs->{attrs}}{qw/where bind/};

  return $fresh_rs->search( {}, {
    from => [{
      $attrs->{alias} => $self->as_query,
      -alias  => $attrs->{alias},
      -rsrc   => $self->result_source,
    }],
    alias => $attrs->{alias},
  });
}

# This code is called by search_related, and makes sure there
# is clear separation between the joins before, during, and
# after the relationship. This information is needed later
# in order to properly resolve prefetch aliases (any alias
# with a relation_chain_depth less than the depth of the
# current prefetch is not considered)
#
# The increments happen twice per join. An even number means a
# relationship specified via a search_related, whereas an odd
# number indicates a join/prefetch added via attributes
#
# Also this code will wrap the current resultset (the one we
# chain to) in a subselect IFF it contains limiting attributes
sub _chain_relationship {
  my ($self, $rel) = @_;
  my $source = $self->result_source;
  my $attrs = { %{$self->{attrs}||{}} };

  # we need to take the prefetch the attrs into account before we
  # ->_resolve_join as otherwise they get lost - captainL
  my $join = $self->_merge_joinpref_attr( $attrs->{join}, $attrs->{prefetch} );

  delete @{$attrs}{qw/join prefetch collapse group_by distinct select as columns +select +as +columns/};

  my $seen = { %{ (delete $attrs->{seen_join}) || {} } };

  my $from;
  my @force_subq_attrs = qw/offset rows group_by having/;

  if (
    ($attrs->{from} && ref $attrs->{from} ne 'ARRAY')
      ||
    $self->_has_resolved_attr (@force_subq_attrs)
  ) {
    # Nuke the prefetch (if any) before the new $rs attrs
    # are resolved (prefetch is useless - we are wrapping
    # a subquery anyway).
    my $rs_copy = $self->search;
    $rs_copy->{attrs}{join} = $self->_merge_joinpref_attr (
      $rs_copy->{attrs}{join},
      delete $rs_copy->{attrs}{prefetch},
    );

    $from = [{
      -rsrc   => $source,
      -alias  => $attrs->{alias},
      $attrs->{alias} => $rs_copy->as_query,
    }];
    delete @{$attrs}{@force_subq_attrs, qw/where bind/};
    $seen->{-relation_chain_depth} = 0;
  }
  elsif ($attrs->{from}) {  #shallow copy suffices
    $from = [ @{$attrs->{from}} ];
  }
  else {
    $from = [{
      -rsrc  => $source,
      -alias => $attrs->{alias},
      $attrs->{alias} => $source->from,
    }];
  }

  my $jpath = ($seen->{-relation_chain_depth})
    ? $from->[-1][0]{-join_path}
    : [];

  my @requested_joins = $source->_resolve_join(
    $join,
    $attrs->{alias},
    $seen,
    $jpath,
  );

  push @$from, @requested_joins;

  $seen->{-relation_chain_depth}++;

  # if $self already had a join/prefetch specified on it, the requested
  # $rel might very well be already included. What we do in this case
  # is effectively a no-op (except that we bump up the chain_depth on
  # the join in question so we could tell it *is* the search_related)
  my $already_joined;

  # we consider the last one thus reverse
  for my $j (reverse @requested_joins) {
    my ($last_j) = keys %{$j->[0]{-join_path}[-1]};
    if ($rel eq $last_j) {
      $j->[0]{-relation_chain_depth}++;
      $already_joined++;
      last;
    }
  }

  unless ($already_joined) {
    push @$from, $source->_resolve_join(
      $rel,
      $attrs->{alias},
      $seen,
      $jpath,
    );
  }

  $seen->{-relation_chain_depth}++;

  return {%$attrs, from => $from, seen_join => $seen};
}

# too many times we have to do $attrs = { %{$self->_resolved_attrs} }
sub _resolved_attrs_copy {
  my $self = shift;
  return { %{$self->_resolved_attrs (@_)} };
}

sub _resolved_attrs {
  my $self = shift;
  return $self->{_attrs} if $self->{_attrs};

  my $attrs  = { %{ $self->{attrs} || {} } };
  my $source = $self->result_source;
  my $alias  = $attrs->{alias};

  # default selection list
  $attrs->{columns} = [ $source->columns ]
    unless List::Util::first { exists $attrs->{$_} } qw/columns cols select as/;

  # merge selectors together
  for (qw/columns select as/) {
    $attrs->{$_} = $self->_merge_attr($attrs->{$_}, delete $attrs->{"+$_"})
      if $attrs->{$_} or $attrs->{"+$_"};
  }

  # disassemble columns
  my (@sel, @as);
  if (my $cols = delete $attrs->{columns}) {
    for my $c (ref $cols eq 'ARRAY' ? @$cols : $cols) {
      if (ref $c eq 'HASH') {
        for my $as (keys %$c) {
          push @sel, $c->{$as};
          push @as, $as;
        }
      }
      else {
        push @sel, $c;
        push @as, $c;
      }
    }
  }

  # when trying to weed off duplicates later do not go past this point -
  # everything added from here on is unbalanced "anyone's guess" stuff
  my $dedup_stop_idx = $#as;

  push @as, @{ ref $attrs->{as} eq 'ARRAY' ? $attrs->{as} : [ $attrs->{as} ] }
    if $attrs->{as};
  push @sel, @{ ref $attrs->{select} eq 'ARRAY' ? $attrs->{select} : [ $attrs->{select} ] }
    if $attrs->{select};

  # assume all unqualified selectors to apply to the current alias (legacy stuff)
  for (@sel) {
    $_ = (ref $_ or $_ =~ /\./) ? $_ : "$alias.$_";
  }

  # disqualify all $alias.col as-bits (collapser mandated)
  for (@as) {
    $_ = ($_ =~ /^\Q$alias.\E(.+)$/) ? $1 : $_;
  }

  # de-duplicate the result (remove *identical* select/as pairs)
  # and also die on duplicate {as} pointing to different {select}s
  # not using a c-style for as the condition is prone to shrinkage
  my $seen;
  my $i = 0;
  while ($i <= $dedup_stop_idx) {
    if ($seen->{"$sel[$i] \x00\x00 $as[$i]"}++) {
      splice @sel, $i, 1;
      splice @as, $i, 1;
      $dedup_stop_idx--;
    }
    elsif ($seen->{$as[$i]}++) {
      $self->throw_exception(
        "inflate_result() alias '$as[$i]' specified twice with different SQL-side {select}-ors"
      );
    }
    else {
      $i++;
    }
  }

  $attrs->{select} = \@sel;
  $attrs->{as} = \@as;

  $attrs->{from} ||= [{
    -rsrc   => $source,
    -alias  => $self->{attrs}{alias},
    $self->{attrs}{alias} => $source->from,
  }];

  if ( $attrs->{join} || $attrs->{prefetch} ) {

    $self->throw_exception ('join/prefetch can not be used with a custom {from}')
      if ref $attrs->{from} ne 'ARRAY';

    my $join = (delete $attrs->{join}) || {};

    if ( defined $attrs->{prefetch} ) {
      $join = $self->_merge_joinpref_attr( $join, $attrs->{prefetch} );
    }

    $attrs->{from} =    # have to copy here to avoid corrupting the original
      [
        @{ $attrs->{from} },
        $source->_resolve_join(
          $join,
          $alias,
          { %{ $attrs->{seen_join} || {} } },
          ( $attrs->{seen_join} && keys %{$attrs->{seen_join}})
            ? $attrs->{from}[-1][0]{-join_path}
            : []
          ,
        )
      ];
  }

  if ( defined $attrs->{order_by} ) {
    $attrs->{order_by} = (
      ref( $attrs->{order_by} ) eq 'ARRAY'
      ? [ @{ $attrs->{order_by} } ]
      : [ $attrs->{order_by} || () ]
    );
  }

  if ($attrs->{group_by} and ref $attrs->{group_by} ne 'ARRAY') {
    $attrs->{group_by} = [ $attrs->{group_by} ];
  }

  # generate the distinct induced group_by early, as prefetch will be carried via a
  # subquery (since a group_by is present)
  if (delete $attrs->{distinct}) {
    if ($attrs->{group_by}) {
      carp_unique ("Useless use of distinct on a grouped resultset ('distinct' is ignored when a 'group_by' is present)");
    }
    else {
      # distinct affects only the main selection part, not what prefetch may
      # add below.
      $attrs->{group_by} = $source->storage->_group_over_selection (
        $attrs->{from},
        $attrs->{select},
        $attrs->{order_by},
      );
    }
  }

  $attrs->{collapse} ||= {};
  if ($attrs->{prefetch}) {

    $self->throw_exception("Unable to prefetch, resultset contains an unnamed selector $attrs->{_dark_selector}{string}")
      if $attrs->{_dark_selector};

    my $prefetch = $self->_merge_joinpref_attr( {}, delete $attrs->{prefetch} );

    my $prefetch_ordering = [];

    # this is a separate structure (we don't look in {from} directly)
    # as the resolver needs to shift things off the lists to work
    # properly (identical-prefetches on different branches)
    my $join_map = {};
    if (ref $attrs->{from} eq 'ARRAY') {

      my $start_depth = $attrs->{seen_join}{-relation_chain_depth} || 0;

      for my $j ( @{$attrs->{from}}[1 .. $#{$attrs->{from}} ] ) {
        next unless $j->[0]{-alias};
        next unless $j->[0]{-join_path};
        next if ($j->[0]{-relation_chain_depth} || 0) < $start_depth;

        my @jpath = map { keys %$_ } @{$j->[0]{-join_path}};

        my $p = $join_map;
        $p = $p->{$_} ||= {} for @jpath[ ($start_depth/2) .. $#jpath]; #only even depths are actual jpath boundaries
        push @{$p->{-join_aliases} }, $j->[0]{-alias};
      }
    }

    my @prefetch =
      $source->_resolve_prefetch( $prefetch, $alias, $join_map, $prefetch_ordering, $attrs->{collapse} );

    # we need to somehow mark which columns came from prefetch
    if (@prefetch) {
      my $sel_end = $#{$attrs->{select}};
      $attrs->{_prefetch_selector_range} = [ $sel_end + 1, $sel_end + @prefetch ];
    }

    push @{ $attrs->{select} }, (map { $_->[0] } @prefetch);
    push @{ $attrs->{as} }, (map { $_->[1] } @prefetch);

    push( @{$attrs->{order_by}}, @$prefetch_ordering );
    $attrs->{_collapse_order_by} = \@$prefetch_ordering;
  }


  # if both page and offset are specified, produce a combined offset
  # even though it doesn't make much sense, this is what pre 081xx has
  # been doing
  if (my $page = delete $attrs->{page}) {
    $attrs->{offset} =
      ($attrs->{rows} * ($page - 1))
            +
      ($attrs->{offset} || 0)
    ;
  }

  return $self->{_attrs} = $attrs;
}

sub _rollout_attr {
  my ($self, $attr) = @_;

  if (ref $attr eq 'HASH') {
    return $self->_rollout_hash($attr);
  } elsif (ref $attr eq 'ARRAY') {
    return $self->_rollout_array($attr);
  } else {
    return [$attr];
  }
}

sub _rollout_array {
  my ($self, $attr) = @_;

  my @rolled_array;
  foreach my $element (@{$attr}) {
    if (ref $element eq 'HASH') {
      push( @rolled_array, @{ $self->_rollout_hash( $element ) } );
    } elsif (ref $element eq 'ARRAY') {
      #  XXX - should probably recurse here
      push( @rolled_array, @{$self->_rollout_array($element)} );
    } else {
      push( @rolled_array, $element );
    }
  }
  return \@rolled_array;
}

sub _rollout_hash {
  my ($self, $attr) = @_;

  my @rolled_array;
  foreach my $key (keys %{$attr}) {
    push( @rolled_array, { $key => $attr->{$key} } );
  }
  return \@rolled_array;
}

sub _calculate_score {
  my ($self, $a, $b) = @_;

  if (defined $a xor defined $b) {
    return 0;
  }
  elsif (not defined $a) {
    return 1;
  }

  if (ref $b eq 'HASH') {
    my ($b_key) = keys %{$b};
    if (ref $a eq 'HASH') {
      my ($a_key) = keys %{$a};
      if ($a_key eq $b_key) {
        return (1 + $self->_calculate_score( $a->{$a_key}, $b->{$b_key} ));
      } else {
        return 0;
      }
    } else {
      return ($a eq $b_key) ? 1 : 0;
    }
  } else {
    if (ref $a eq 'HASH') {
      my ($a_key) = keys %{$a};
      return ($b eq $a_key) ? 1 : 0;
    } else {
      return ($b eq $a) ? 1 : 0;
    }
  }
}

sub _merge_joinpref_attr {
  my ($self, $orig, $import) = @_;

  return $import unless defined($orig);
  return $orig unless defined($import);

  $orig = $self->_rollout_attr($orig);
  $import = $self->_rollout_attr($import);

  my $seen_keys;
  foreach my $import_element ( @{$import} ) {
    # find best candidate from $orig to merge $b_element into
    my $best_candidate = { position => undef, score => 0 }; my $position = 0;
    foreach my $orig_element ( @{$orig} ) {
      my $score = $self->_calculate_score( $orig_element, $import_element );
      if ($score > $best_candidate->{score}) {
        $best_candidate->{position} = $position;
        $best_candidate->{score} = $score;
      }
      $position++;
    }
    my ($import_key) = ( ref $import_element eq 'HASH' ) ? keys %{$import_element} : ($import_element);
    $import_key = '' if not defined $import_key;

    if ($best_candidate->{score} == 0 || exists $seen_keys->{$import_key}) {
      push( @{$orig}, $import_element );
    } else {
      my $orig_best = $orig->[$best_candidate->{position}];
      # merge orig_best and b_element together and replace original with merged
      if (ref $orig_best ne 'HASH') {
        $orig->[$best_candidate->{position}] = $import_element;
      } elsif (ref $import_element eq 'HASH') {
        my ($key) = keys %{$orig_best};
        $orig->[$best_candidate->{position}] = { $key => $self->_merge_joinpref_attr($orig_best->{$key}, $import_element->{$key}) };
      }
    }
    $seen_keys->{$import_key} = 1; # don't merge the same key twice
  }

  return $orig;
}

{
  my $hm;

  sub _merge_attr {
    $hm ||= do {
      require Hash::Merge;
      my $hm = Hash::Merge->new;

      $hm->specify_behavior({
        SCALAR => {
          SCALAR => sub {
            my ($defl, $defr) = map { defined $_ } (@_[0,1]);

            if ($defl xor $defr) {
              return [ $defl ? $_[0] : $_[1] ];
            }
            elsif (! $defl) {
              return [];
            }
            elsif (__HM_DEDUP and $_[0] eq $_[1]) {
              return [ $_[0] ];
            }
            else {
              return [$_[0], $_[1]];
            }
          },
          ARRAY => sub {
            return $_[1] if !defined $_[0];
            return $_[1] if __HM_DEDUP and List::Util::first { $_ eq $_[0] } @{$_[1]};
            return [$_[0], @{$_[1]}]
          },
          HASH  => sub {
            return [] if !defined $_[0] and !keys %{$_[1]};
            return [ $_[1] ] if !defined $_[0];
            return [ $_[0] ] if !keys %{$_[1]};
            return [$_[0], $_[1]]
          },
        },
        ARRAY => {
          SCALAR => sub {
            return $_[0] if !defined $_[1];
            return $_[0] if __HM_DEDUP and List::Util::first { $_ eq $_[1] } @{$_[0]};
            return [@{$_[0]}, $_[1]]
          },
          ARRAY => sub {
            my @ret = @{$_[0]} or return $_[1];
            return [ @ret, @{$_[1]} ] unless __HM_DEDUP;
            my %idx = map { $_ => 1 } @ret;
            push @ret, grep { ! defined $idx{$_} } (@{$_[1]});
            \@ret;
          },
          HASH => sub {
            return [ $_[1] ] if ! @{$_[0]};
            return $_[0] if !keys %{$_[1]};
            return $_[0] if __HM_DEDUP and List::Util::first { $_ eq $_[1] } @{$_[0]};
            return [ @{$_[0]}, $_[1] ];
          },
        },
        HASH => {
          SCALAR => sub {
            return [] if !keys %{$_[0]} and !defined $_[1];
            return [ $_[0] ] if !defined $_[1];
            return [ $_[1] ] if !keys %{$_[0]};
            return [$_[0], $_[1]]
          },
          ARRAY => sub {
            return [] if !keys %{$_[0]} and !@{$_[1]};
            return [ $_[0] ] if !@{$_[1]};
            return $_[1] if !keys %{$_[0]};
            return $_[1] if __HM_DEDUP and List::Util::first { $_ eq $_[0] } @{$_[1]};
            return [ $_[0], @{$_[1]} ];
          },
          HASH => sub {
            return [] if !keys %{$_[0]} and !keys %{$_[1]};
            return [ $_[0] ] if !keys %{$_[1]};
            return [ $_[1] ] if !keys %{$_[0]};
            return [ $_[0] ] if $_[0] eq $_[1];
            return [ $_[0], $_[1] ];
          },
        }
      } => 'DBIC_RS_ATTR_MERGER');
      $hm;
    };

    return $hm->merge ($_[1], $_[2]);
  }
}

sub STORABLE_freeze {
  my ($self, $cloning) = @_;
  my $to_serialize = { %$self };

  # A cursor in progress can't be serialized (and would make little sense anyway)
  delete $to_serialize->{cursor};

  # nor is it sensical to store a not-yet-fired-count pager
  if ($to_serialize->{pager} and ref $to_serialize->{pager}{total_entries} eq 'CODE') {
    delete $to_serialize->{pager};
  }

  Storable::nfreeze($to_serialize);
}

# need this hook for symmetry
sub STORABLE_thaw {
  my ($self, $cloning, $serialized) = @_;

  %$self = %{ Storable::thaw($serialized) };

  $self;
}


=head2 throw_exception

See L<DBIx::Class::Schema/throw_exception> for details.

=cut

sub throw_exception {
  my $self=shift;

  if (ref $self and my $rsrc = $self->result_source) {
    $rsrc->throw_exception(@_)
  }
  else {
    DBIx::Class::Exception->throw(@_);
  }
}

# XXX: FIXME: Attributes docs need clearing up

=head1 ATTRIBUTES

Attributes are used to refine a ResultSet in various ways when
searching for data. They can be passed to any method which takes an
C<\%attrs> argument. See L</search>, L</search_rs>, L</find>,
L</count>.

These are in no particular order:

=head2 order_by

=over 4

=item Value: ( $order_by | \@order_by | \%order_by )

=back

Which column(s) to order the results by.

[The full list of suitable values is documented in
L<SQL::Abstract/"ORDER BY CLAUSES">; the following is a summary of
common options.]

If a single column name, or an arrayref of names is supplied, the
argument is passed through directly to SQL. The hashref syntax allows
for connection-agnostic specification of ordering direction:

 For descending order:

  order_by => { -desc => [qw/col1 col2 col3/] }

 For explicit ascending order:

  order_by => { -asc => 'col' }

The old scalarref syntax (i.e. order_by => \'year DESC') is still
supported, although you are strongly encouraged to use the hashref
syntax as outlined above.

=head2 columns

=over 4

=item Value: \@columns

=back

Shortcut to request a particular set of columns to be retrieved. Each
column spec may be a string (a table column name), or a hash (in which
case the key is the C<as> value, and the value is used as the C<select>
expression). Adds C<me.> onto the start of any column without a C<.> in
it and sets C<select> from that, then auto-populates C<as> from
C<select> as normal. (You may also use the C<cols> attribute, as in
earlier versions of DBIC.)

Essentially C<columns> does the same as L</select> and L</as>.

    columns => [ 'foo', { bar => 'baz' } ]

is the same as

    select => [qw/foo baz/],
    as => [qw/foo bar/]

=head2 +columns

=over 4

=item Value: \@columns

=back

Indicates additional columns to be selected from storage. Works the same
as L</columns> but adds columns to the selection. (You may also use the
C<include_columns> attribute, as in earlier versions of DBIC). For
example:-

  $schema->resultset('CD')->search(undef, {
    '+columns' => ['artist.name'],
    join => ['artist']
  });

would return all CDs and include a 'name' column to the information
passed to object inflation. Note that the 'artist' is the name of the
column (or relationship) accessor, and 'name' is the name of the column
accessor in the related table.

B<NOTE:> You need to explicitly quote '+columns' when defining the attribute.
Not doing so causes Perl to incorrectly interpret +columns as a bareword with a
unary plus operator before it.

=head2 include_columns

=over 4

=item Value: \@columns

=back

Deprecated.  Acts as a synonym for L</+columns> for backward compatibility.

=head2 select

=over 4

=item Value: \@select_columns

=back

Indicates which columns should be selected from the storage. You can use
column names, or in the case of RDBMS back ends, function or stored procedure
names:

  $rs = $schema->resultset('Employee')->search(undef, {
    select => [
      'name',
      { count => 'employeeid' },
      { max => { length => 'name' }, -as => 'longest_name' }
    ]
  });

  # Equivalent SQL
  SELECT name, COUNT( employeeid ), MAX( LENGTH( name ) ) AS longest_name FROM employee

B<NOTE:> You will almost always need a corresponding L</as> attribute when you
use L</select>, to instruct DBIx::Class how to store the result of the column.
Also note that the L</as> attribute has nothing to do with the SQL-side 'AS'
identifier aliasing. You can however alias a function, so you can use it in
e.g. an C<ORDER BY> clause. This is done via the C<-as> B<select function
attribute> supplied as shown in the example above.

B<NOTE:> You need to explicitly quote '+select'/'+as' when defining the attributes.
Not doing so causes Perl to incorrectly interpret them as a bareword with a
unary plus operator before it.

=head2 +select

=over 4

Indicates additional columns to be selected from storage.  Works the same as
L</select> but adds columns to the default selection, instead of specifying
an explicit list.

=back

=head2 +as

=over 4

Indicates additional column names for those added via L</+select>. See L</as>.

=back

=head2 as

=over 4

=item Value: \@inflation_names

=back

Indicates column names for object inflation. That is L</as> indicates the
slot name in which the column value will be stored within the
L<Row|DBIx::Class::Row> object. The value will then be accessible via this
identifier by the C<get_column> method (or via the object accessor B<if one
with the same name already exists>) as shown below. The L</as> attribute has
B<nothing to do> with the SQL-side C<AS>. See L</select> for details.

  $rs = $schema->resultset('Employee')->search(undef, {
    select => [
      'name',
      { count => 'employeeid' },
      { max => { length => 'name' }, -as => 'longest_name' }
    ],
    as => [qw/
      name
      employee_count
      max_name_length
    /],
  });

If the object against which the search is performed already has an accessor
matching a column name specified in C<as>, the value can be retrieved using
the accessor as normal:

  my $name = $employee->name();

If on the other hand an accessor does not exist in the object, you need to
use C<get_column> instead:

  my $employee_count = $employee->get_column('employee_count');

You can create your own accessors if required - see
L<DBIx::Class::Manual::Cookbook> for details.

=head2 join

=over 4

=item Value: ($rel_name | \@rel_names | \%rel_names)

=back

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

You need to use the relationship (not the table) name in  conditions,
because they are aliased as such. The current table is aliased as "me", so
you need to use me.column_name in order to avoid ambiguity. For example:

  # Get CDs from 1984 with a 'Foo' track
  my $rs = $schema->resultset('CD')->search(
    {
      'me.year' => 1984,
      'tracks.name' => 'Foo'
    },
    { join => 'tracks' }
  );

If the same join is supplied twice, it will be aliased to <rel>_2 (and
similarly for a third time). For e.g.

  my $rs = $schema->resultset('Artist')->search({
    'cds.title'   => 'Down to Earth',
    'cds_2.title' => 'Popular',
  }, {
    join => [ qw/cds cds/ ],
  });

will return a set of all artists that have both a cd with title 'Down
to Earth' and a cd with title 'Popular'.

If you want to fetch related objects from other tables as well, see C<prefetch>
below.

For more help on using joins with search, see L<DBIx::Class::Manual::Joining>.

=head2 prefetch

=over 4

=item Value: ($rel_name | \@rel_names | \%rel_names)

=back

Contains one or more relationships that should be fetched along with
the main query (when they are accessed afterwards the data will
already be available, without extra queries to the database).  This is
useful for when you know you will need the related objects, because it
saves at least one query:

  my $rs = $schema->resultset('Tag')->search(
    undef,
    {
      prefetch => {
        cd => 'artist'
      }
    }
  );

The initial search results in SQL like the following:

  SELECT tag.*, cd.*, artist.* FROM tag
  JOIN cd ON tag.cd = cd.cdid
  JOIN artist ON cd.artist = artist.artistid

L<DBIx::Class> has no need to go back to the database when we access the
C<cd> or C<artist> relationships, which saves us two SQL statements in this
case.

Simple prefetches will be joined automatically, so there is no need
for a C<join> attribute in the above search.

L</prefetch> can be used with the any of the relationship types and
multiple prefetches can be specified together. Below is a more complex
example that prefetches a CD's artist, its liner notes (if present),
the cover image, the tracks on that cd, and the guests on those
tracks.

 # Assuming:
 My::Schema::CD->belongs_to( artist      => 'My::Schema::Artist'     );
 My::Schema::CD->might_have( liner_note  => 'My::Schema::LinerNotes' );
 My::Schema::CD->has_one(    cover_image => 'My::Schema::Artwork'    );
 My::Schema::CD->has_many(   tracks      => 'My::Schema::Track'      );

 My::Schema::Artist->belongs_to( record_label => 'My::Schema::RecordLabel' );

 My::Schema::Track->has_many( guests => 'My::Schema::Guest' );


 my $rs = $schema->resultset('CD')->search(
   undef,
   {
     prefetch => [
       { artist => 'record_label'},  # belongs_to => belongs_to
       'liner_note',                 # might_have
       'cover_image',                # has_one
       { tracks => 'guests' },       # has_many => has_many
     ]
   }
 );

This will produce SQL like the following:

 SELECT cd.*, artist.*, record_label.*, liner_note.*, cover_image.*,
        tracks.*, guests.*
   FROM cd me
   JOIN artist artist
     ON artist.artistid = me.artistid
   JOIN record_label record_label
     ON record_label.labelid = artist.labelid
   LEFT JOIN track tracks
     ON tracks.cdid = me.cdid
   LEFT JOIN guest guests
     ON guests.trackid = track.trackid
   LEFT JOIN liner_notes liner_note
     ON liner_note.cdid = me.cdid
   JOIN cd_artwork cover_image
     ON cover_image.cdid = me.cdid
 ORDER BY tracks.cd

Now the C<artist>, C<record_label>, C<liner_note>, C<cover_image>,
C<tracks>, and C<guests> of the CD will all be available through the
relationship accessors without the need for additional queries to the
database.

However, there is one caveat to be observed: it can be dangerous to
prefetch more than one L<has_many|DBIx::Class::Relationship/has_many>
relationship on a given level. e.g.:

 my $rs = $schema->resultset('CD')->search(
   undef,
   {
     prefetch => [
       'tracks',                         # has_many
       { cd_to_producer => 'producer' }, # has_many => belongs_to (i.e. m2m)
     ]
   }
 );

In fact, C<DBIx::Class> will emit the following warning:

 Prefetching multiple has_many rels tracks and cd_to_producer at top
 level will explode the number of row objects retrievable via ->next
 or ->all. Use at your own risk.

The collapser currently can't identify duplicate tuples for multiple
L<has_many|DBIx::Class::Relationship/has_many> relationships and as a
result the second L<has_many|DBIx::Class::Relationship/has_many>
relation could contain redundant objects.

=head3 Using L</prefetch> with L</join>

L</prefetch> implies a L</join> with the equivalent argument, and is
properly merged with any existing L</join> specification. So the
following:

  my $rs = $schema->resultset('CD')->search(
   {'record_label.name' => 'Music Product Ltd.'},
   {
     join     => {artist => 'record_label'},
     prefetch => 'artist',
   }
 );

... will work, searching on the record label's name, but only
prefetching the C<artist>.

=head3 Using L</prefetch> with L</select> / L</+select> / L</as> / L</+as>

L</prefetch> implies a L</+select>/L</+as> with the fields of the
prefetched relations.  So given:

  my $rs = $schema->resultset('CD')->search(
   undef,
   {
     select   => ['cd.title'],
     as       => ['cd_title'],
     prefetch => 'artist',
   }
 );

The L</select> becomes: C<'cd.title', 'artist.*'> and the L</as>
becomes: C<'cd_title', 'artist.*'>.

=head3 CAVEATS

Prefetch does a lot of deep magic. As such, it may not behave exactly
as you might expect.

=over 4

=item *

Prefetch uses the L</cache> to populate the prefetched relationships. This
may or may not be what you want.

=item *

If you specify a condition on a prefetched relationship, ONLY those
rows that match the prefetched condition will be fetched into that relationship.
This means that adding prefetch to a search() B<may alter> what is returned by
traversing a relationship. So, if you have C<< Artist->has_many(CDs) >> and you do

  my $artist_rs = $schema->resultset('Artist')->search({
      'cds.year' => 2008,
  }, {
      join => 'cds',
  });

  my $count = $artist_rs->first->cds->count;

  my $artist_rs_prefetch = $artist_rs->search( {}, { prefetch => 'cds' } );

  my $prefetch_count = $artist_rs_prefetch->first->cds->count;

  cmp_ok( $count, '==', $prefetch_count, "Counts should be the same" );

that cmp_ok() may or may not pass depending on the datasets involved. This
behavior may or may not survive the 0.09 transition.

=back

=head2 page

=over 4

=item Value: $page

=back

Makes the resultset paged and specifies the page to retrieve. Effectively
identical to creating a non-pages resultset and then calling ->page($page)
on it.

If L</rows> attribute is not specified it defaults to 10 rows per page.

When you have a paged resultset, L</count> will only return the number
of rows in the page. To get the total, use the L</pager> and call
C<total_entries> on it.

=head2 rows

=over 4

=item Value: $rows

=back

Specifies the maximum number of rows for direct retrieval or the number of
rows per page if the page attribute or method is used.

=head2 offset

=over 4

=item Value: $offset

=back

Specifies the (zero-based) row number for the  first row to be returned, or the
of the first row of the first page if paging is used.

=head2 group_by

=over 4

=item Value: \@columns

=back

A arrayref of columns to group by. Can include columns of joined tables.

  group_by => [qw/ column1 column2 ... /]

=head2 having

=over 4

=item Value: $condition

=back

HAVING is a select statement attribute that is applied between GROUP BY and
ORDER BY. It is applied to the after the grouping calculations have been
done.

  having => { 'count_employee' => { '>=', 100 } }

or with an in-place function in which case literal SQL is required:

  having => \[ 'count(employee) >= ?', [ count => 100 ] ]

=head2 distinct

=over 4

=item Value: (0 | 1)

=back

Set to 1 to group by all columns. If the resultset already has a group_by
attribute, this setting is ignored and an appropriate warning is issued.

=head2 where

=over 4

Adds to the WHERE clause.

  # only return rows WHERE deleted IS NULL for all searches
  __PACKAGE__->resultset_attributes({ where => { deleted => undef } }); )

Can be overridden by passing C<< { where => undef } >> as an attribute
to a resultset.

=back

=head2 cache

Set to 1 to cache search results. This prevents extra SQL queries if you
revisit rows in your ResultSet:

  my $resultset = $schema->resultset('Artist')->search( undef, { cache => 1 } );

  while( my $artist = $resultset->next ) {
    ... do stuff ...
  }

  $rs->first; # without cache, this would issue a query

By default, searches are not cached.

For more examples of using these attributes, see
L<DBIx::Class::Manual::Cookbook>.

=head2 for

=over 4

=item Value: ( 'update' | 'shared' )

=back

Set to 'update' for a SELECT ... FOR UPDATE or 'shared' for a SELECT
... FOR SHARED.

=cut

1;
