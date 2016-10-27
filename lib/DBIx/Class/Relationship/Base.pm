package DBIx::Class::Relationship::Base;

use strict;
use warnings;

use base qw/DBIx::Class/;

use Scalar::Util qw/weaken blessed/;
use DBIx::Class::_Util qw(
  UNRESOLVABLE_CONDITION DUMMY_ALIASPAIR
  dbic_internal_try dbic_internal_catch fail_on_internal_call
);
use DBIx::Class::SQLMaker::Util 'extract_equality_conditions';
use DBIx::Class::Carp;

# FIXME - this should go away
# instead Carp::Skip should export usable keywords or something like that
my $unique_carper;
BEGIN { $unique_carper = \&carp_unique }

use namespace::clean;

=head1 NAME

DBIx::Class::Relationship::Base - Inter-table relationships

=head1 SYNOPSIS

  __PACKAGE__->add_relationship(
    spiders => 'My::DB::Result::Creatures',
    sub {
      my $args = shift;
      return {
        "$args->{foreign_alias}.id"   => { -ident => "$args->{self_alias}.id" },
        "$args->{foreign_alias}.type" => 'arachnid'
      };
    },
  );

=head1 DESCRIPTION

This class provides methods to describe the relationships between the
tables in your database model. These are the "bare bones" relationships
methods, for predefined ones, look in L<DBIx::Class::Relationship>.

=head1 METHODS

=head2 add_relationship

=over 4

=item Arguments: $rel_name, $foreign_class, $condition, $attrs

=back

  __PACKAGE__->add_relationship('rel_name',
                                'Foreign::Class',
                                $condition, $attrs);

Create a custom relationship between one result source and another
source, indicated by its class name.

=head3 condition

The condition argument describes the C<ON> clause of the C<JOIN>
expression used to connect the two sources when creating SQL queries.

=head4 Simple equality

To create simple equality joins, supply a hashref containing the remote
table column name as the key(s) prefixed by C<'foreign.'>, and the
corresponding local table column name as the value(s) prefixed by C<'self.'>.
Both C<foreign> and C<self> are pseudo aliases and must be entered
literally. They will be replaced with the actual correct table alias
when the SQL is produced.

For example given:

  My::Schema::Author->has_many(
    books => 'My::Schema::Book',
    { 'foreign.author_id' => 'self.id' }
  );

A query like:

  $author_rs->search_related('books')->next

will result in the following C<JOIN> clause:

  ... FROM author me LEFT JOIN book books ON books.author_id = me.id ...

This describes a relationship between the C<Author> table and the
C<Book> table where the C<Book> table has a column C<author_id>
containing the ID value of the C<Author>.

Similarly:

  My::Schema::Book->has_many(
    editions => 'My::Schema::Edition',
    {
      'foreign.publisher_id' => 'self.publisher_id',
      'foreign.type_id'      => 'self.type_id',
    }
  );

  ...

  $book_rs->search_related('editions')->next

will result in the C<JOIN> clause:

  ... FROM book me
      LEFT JOIN edition editions ON
           editions.publisher_id = me.publisher_id
       AND editions.type_id = me.type_id ...

This describes the relationship from C<Book> to C<Edition>, where the
C<Edition> table refers to a publisher and a type (e.g. "paperback"):

=head4 Multiple groups of simple equality conditions

As is the default in L<SQL::Abstract>, the key-value pairs will be
C<AND>ed in the resulting C<JOIN> clause. An C<OR> can be achieved with
an arrayref. For example a condition like:

  My::Schema::Item->has_many(
    related_item_links => My::Schema::Item::Links,
    [
      { 'foreign.left_itemid'  => 'self.id' },
      { 'foreign.right_itemid' => 'self.id' },
    ],
  );

will translate to the following C<JOIN> clause:

 ... FROM item me JOIN item_relations related_item_links ON
         related_item_links.left_itemid = me.id
      OR related_item_links.right_itemid = me.id ...

This describes the relationship from C<Item> to C<Item::Links>, where
C<Item::Links> is a many-to-many linking table, linking items back to
themselves in a peer fashion (without a "parent-child" designation)

=head4 Custom join conditions

  NOTE: The custom join condition specification mechanism is capable of
  generating JOIN clauses of virtually unlimited complexity. This may limit
  your ability to traverse some of the more involved relationship chains the
  way you expect, *and* may bring your RDBMS to its knees. Exercise care
  when declaring relationships as described here.

To specify joins which describe more than a simple equality of column
values, the custom join condition coderef syntax can be used. For
example:

  My::Schema::Artist->has_many(
    cds_80s => 'My::Schema::CD',
    sub {
      my $args = shift;

      return {
        "$args->{foreign_alias}.artist" => { -ident => "$args->{self_alias}.artistid" },
        "$args->{foreign_alias}.year"   => { '>', "1979", '<', "1990" },
      };
    }
  );

  ...

  $artist_rs->search_related('cds_80s')->next;

will result in the C<JOIN> clause:

  ... FROM artist me LEFT JOIN cd cds_80s ON
        cds_80s.artist = me.artistid
    AND cds_80s.year < ?
    AND cds_80s.year > ?

with the bind values:

   '1990', '1979'

C<< $args->{foreign_alias} >> and C<< $args->{self_alias} >> are supplied the
same values that would be otherwise substituted for C<foreign> and C<self>
in the simple hashref syntax case.

The coderef is expected to return a valid L<SQL::Abstract> query-structure, just
like what one would supply as the first argument to
L<DBIx::Class::ResultSet/search>. The return value will be passed directly to
L<SQL::Abstract> and the resulting SQL will be used verbatim as the C<ON>
clause of the C<JOIN> statement associated with this relationship.

While every coderef-based condition must return a valid C<ON> clause, it may
elect to additionally return a simplified B<optional> join-free condition
consisting of a hashref with B<all keys being fully qualified names of columns
declared on the corresponding result source>. This boils down to two scenarios:

=over

=item *

When relationship resolution is invoked after C<< $result->$rel_name >>, as
opposed to C<< $rs->related_resultset($rel_name) >>, the C<$result> object
is passed to the coderef as C<< $args->{self_result_object} >>.

=item *

Alternatively when the user-space invokes resolution via
C<< $result->set_from_related( $rel_name => $foreign_values_or_object ) >>, the
corresponding data is passed to the coderef as C<< $args->{foreign_values} >>,
B<always> in the form of a hashref. If a foreign result object is supplied
(which is valid usage of L</set_from_related>), its values will be extracted
into hashref form by calling L<get_columns|DBIx::Class::Row/get_columns>.

=back

Note that the above scenarios are mutually exclusive, that is you will be supplied
none or only one of C<self_result_object> and C<foreign_values>. In other words if
you define your condition coderef as:

  sub {
    my $args = shift;

    return (
      {
        "$args->{foreign_alias}.artist" => { -ident => "$args->{self_alias}.artistid" },
        "$args->{foreign_alias}.year"   => { '>', "1979", '<', "1990" },
      },
      ! $args->{self_result_object} ? () : {
        "$args->{foreign_alias}.artist" => $args->{self_result_object}->artistid,
        "$args->{foreign_alias}.year"   => { '>', "1979", '<', "1990" },
      },
      ! $args->{foreign_values} ? () : {
        "$args->{self_alias}.artistid" => $args->{foreign_values}{artist},
      }
    );
  }

Then this code:

    my $artist = $schema->resultset("Artist")->find({ id => 4 });
    $artist->cds_80s->all;

Can skip a C<JOIN> altogether and instead produce:

    SELECT cds_80s.cdid, cds_80s.artist, cds_80s.title, cds_80s.year, cds_80s.genreid, cds_80s.single_track
      FROM cd cds_80s
      WHERE cds_80s.artist = ?
        AND cds_80s.year < ?
        AND cds_80s.year > ?

With the bind values:

    '4', '1990', '1979'

While this code:

    my $cd = $schema->resultset("CD")->search({ artist => 1 }, { rows => 1 })->single;
    my $artist = $schema->resultset("Artist")->new({});
    $artist->set_from_related('cds_80s');

Will properly set the C<< $artist->artistid >> field of this new object to C<1>

Note that in order to be able to use L</set_from_related> (and by extension
L<< $result->create_related|DBIx::Class::Relationship::Base/create_related >>),
the returned join free condition B<must> contain only plain values/deflatable
objects. For instance the C<year> constraint in the above example prevents
the relationship from being used to create related objects using
C<< $artst->create_related( cds_80s => { title => 'blah' } ) >> (an
exception will be thrown).

In order to allow the user to go truly crazy when generating a custom C<ON>
clause, the C<$args> hashref passed to the subroutine contains some extra
metadata. Currently the supplied coderef is executed as:

  $relationship_info->{cond}->({
    self_resultsource   => The resultsource instance on which rel_name is registered
    rel_name            => The relationship name (does *NOT* always match foreign_alias)

    self_alias          => The alias of the invoking resultset
    foreign_alias       => The alias of the to-be-joined resultset (does *NOT* always match rel_name)

    # only one of these (or none at all) will ever be supplied to aid in the
    # construction of a join-free condition

    self_result_object  => The invocant *object* itself in case of a call like
                           $result_object->$rel_name( ... )

    foreign_values      => A *hashref* of related data: may be passed in directly or
                           derived via ->get_columns() from a related object in case of
                           $result_object->set_from_related( $rel_name, $foreign_result_object )

    # deprecated inconsistent names, will be forever available for legacy code
    self_rowobj         => Old deprecated slot for self_result_object
    foreign_relname     => Old deprecated slot for rel_name
  });

=head3 attributes

The L<standard ResultSet attributes|DBIx::Class::ResultSet/ATTRIBUTES> may
be used as relationship attributes. In particular, the 'where' attribute is
useful for filtering relationships:

     __PACKAGE__->has_many( 'valid_users', 'MyApp::Schema::User',
        { 'foreign.user_id' => 'self.user_id' },
        { where => { valid => 1 } }
    );

The following attributes are also valid:

=over 4

=item join_type

Explicitly specifies the type of join to use in the relationship. Any SQL
join type is valid, e.g. C<LEFT> or C<RIGHT>. It will be placed in the SQL
command immediately before C<JOIN>.

=item proxy =E<gt> $column | \@columns | \%column

The 'proxy' attribute can be used to retrieve values, and to perform
updates if the relationship has 'cascade_update' set. The 'might_have'
and 'has_one' relationships have this set by default; if you want a proxy
to update across a 'belongs_to' relationship, you must set the attribute
yourself.

=over 4

=item \@columns

An arrayref containing a list of accessors in the foreign class to create in
the main class. If, for example, you do the following:

  MyApp::Schema::CD->might_have(liner_notes => 'MyApp::Schema::LinerNotes',
    undef, {
      proxy => [ qw/notes/ ],
    });

Then, assuming MyApp::Schema::LinerNotes has an accessor named notes, you can do:

  my $cd = MyApp::Schema::CD->find(1);
  $cd->notes('Notes go here'); # set notes -- LinerNotes object is
                               # created if it doesn't exist

For a 'belongs_to relationship, note the 'cascade_update':

  MyApp::Schema::Track->belongs_to( cd => 'MyApp::Schema::CD', 'cd',
      { proxy => ['title'], cascade_update => 1 }
  );
  $track->title('New Title');
  $track->update; # updates title in CD

=item \%column

A hashref where each key is the accessor you want installed in the main class,
and its value is the name of the original in the foreign class.

  MyApp::Schema::Track->belongs_to( cd => 'MyApp::Schema::CD', 'cd',
      { proxy => { cd_title => 'title' } }
  );

This will create an accessor named C<cd_title> on the C<$track> result object.

=back

NOTE: you can pass a nested struct too, for example:

  MyApp::Schema::Track->belongs_to( cd => 'MyApp::Schema::CD', 'cd',
    { proxy => [ 'year', { cd_title => 'title' } ] }
  );

=item accessor

Specifies the type of accessor that should be created for the relationship.
Valid values are C<single> (for when there is only a single related object),
C<multi> (when there can be many), and C<filter> (for when there is a single
related object, but you also want the relationship accessor to double as
a column accessor). For C<multi> accessors, an add_to_* method is also
created, which calls C<create_related> for the relationship.

=item is_foreign_key_constraint

If you are using L<SQL::Translator> to create SQL for you and you find that it
is creating constraints where it shouldn't, or not creating them where it
should, set this attribute to a true or false value to override the detection
of when to create constraints.

=item cascade_copy

If C<cascade_copy> is true on a C<has_many> relationship for an
object, then when you copy the object all the related objects will
be copied too. To turn this behaviour off, pass C<< cascade_copy => 0 >>
in the C<$attr> hashref.

The behaviour defaults to C<< cascade_copy => 1 >> for C<has_many>
relationships.

=item cascade_delete

By default, DBIx::Class cascades deletes across C<has_many>,
C<has_one> and C<might_have> relationships. You can disable this
behaviour on a per-relationship basis by supplying
C<< cascade_delete => 0 >> in the relationship attributes.

The cascaded operations are performed after the requested delete,
so if your database has a constraint on the relationship, it will
have deleted/updated the related records or raised an exception
before DBIx::Class gets to perform the cascaded operation.

=item cascade_update

By default, DBIx::Class cascades updates across C<has_one> and
C<might_have> relationships. You can disable this behaviour on a
per-relationship basis by supplying C<< cascade_update => 0 >> in
the relationship attributes.

The C<belongs_to> relationship does not update across relationships
by default, so if you have a 'proxy' attribute on a belongs_to and want to
use 'update' on it, you must set C<< cascade_update => 1 >>.

This is not a RDMS style cascade update - it purely means that when
an object has update called on it, all the related objects also
have update called. It will not change foreign keys automatically -
you must arrange to do this yourself.

=item on_delete / on_update

If you are using L<SQL::Translator> to create SQL for you, you can use these
attributes to explicitly set the desired C<ON DELETE> or C<ON UPDATE> constraint
type. If not supplied the SQLT parser will attempt to infer the constraint type by
interrogating the attributes of the B<opposite> relationship. For any 'multi'
relationship with C<< cascade_delete => 1 >>, the corresponding belongs_to
relationship will be created with an C<ON DELETE CASCADE> constraint. For any
relationship bearing C<< cascade_copy => 1 >> the resulting belongs_to constraint
will be C<ON UPDATE CASCADE>. If you wish to disable this autodetection, and just
use the RDBMS' default constraint type, pass C<< on_delete => undef >> or
C<< on_delete => '' >>, and the same for C<on_update> respectively.

=item is_deferrable

Tells L<SQL::Translator> that the foreign key constraint it creates should be
deferrable. In other words, the user may request that the constraint be ignored
until the end of the transaction. Currently, only the PostgreSQL producer
actually supports this.

=item add_fk_index

Tells L<SQL::Translator> to add an index for this constraint. Can also be
specified globally in the args to L<DBIx::Class::Schema/deploy> or
L<DBIx::Class::Schema/create_ddl_dir>. Default is on, set to 0 to disable.

=back

=head2 register_relationship

=over 4

=item Arguments: $rel_name, $rel_info

=back

Registers a relationship on the class. This is called internally by
DBIx::Class::ResultSourceProxy to set up Accessors and Proxies.

=cut

sub register_relationship { }

=head2 related_resultset

=over 4

=item Arguments: $rel_name

=item Return Value: L<$related_resultset|DBIx::Class::ResultSet>

=back

  $rs = $cd->related_resultset('artist');

Returns a L<DBIx::Class::ResultSet> for the relationship named
$rel_name.

=head2 $relationship_accessor

=over 4

=item Arguments: none

=item Return Value: L<$result|DBIx::Class::Manual::ResultClass> | L<$related_resultset|DBIx::Class::ResultSet> | undef

=back

  # These pairs do the same thing
  $result = $cd->related_resultset('artist')->single;  # has_one relationship
  $result = $cd->artist;
  $rs = $cd->related_resultset('tracks');           # has_many relationship
  $rs = $cd->tracks;

This is the recommended way to traverse through relationships, based
on the L</accessor> name given in the relationship definition.

This will return either a L<Result|DBIx::Class::Manual::ResultClass> or a
L<ResultSet|DBIx::Class::ResultSet>, depending on if the relationship is
C<single> (returns only one row) or C<multi> (returns many rows).  The
method may also return C<undef> if the relationship doesn't exist for
this instance (like in the case of C<might_have> relationships).

=cut

sub related_resultset {
  $_[0]->throw_exception(
    '$result->related_resultset() no longer accepts extra search arguments, '
  . 'you need to switch to ...->related_resultset($relname)->search_rs(...) '
  . 'instead (it was never documented and more importantly could never work '
  . 'reliably due to the heavy caching involved)'
  ) if @_ > 2;

  $_[0]->throw_exception("Can't call *_related as class methods")
    unless ref $_[0];

  return $_[0]->{related_resultsets}{$_[1]}
    if defined $_[0]->{related_resultsets}{$_[1]};

  my ($self, $rel) = @_;

  my $rsrc = $self->result_source;

  my $rel_info = $rsrc->relationship_info($rel)
    or $self->throw_exception( "No such relationship '$rel'" );

  my $relcond_is_freeform = ref $rel_info->{cond} eq 'CODE';

  my $rrc_args = {
    rel_name => $rel,
    self_result_object => $self,

    # an extra sanity check guard
    require_join_free_condition => !!(
      ! $relcond_is_freeform
        and
      $self->in_storage
    ),

    # an API where these are optional would be too cumbersome,
    # instead always pass in some dummy values
    DUMMY_ALIASPAIR,

    # this may look weird, but remember that we are making a resultset
    # out of an existing object, with the new source being at the head
    # of the FROM chain. Having a 'me' alias is nothing but expected there
    foreign_alias => 'me',
  };

  my $jfc = (
    # In certain extraordinary circumstances the relationship resolution may
    # throw (e.g. when walking through elaborate custom conds)
    # In case the object is "real" (i.e. in_storage) we just go ahead and
    # let the exception surface. Otherwise we carp and move on.
    #
    # The elaborate code-duplicating ternary is there because the xsified
    # ->in_storage() is orders of magnitude faster than the Try::Tiny-like
    # construct below ( perl's low level tooling is truly shit :/ )
    ( $self->in_storage or DBIx::Class::_Util::in_internal_try )
      ? $rsrc->resolve_relationship_condition($rrc_args)->{join_free_condition}
      : dbic_internal_try {
          $rsrc->resolve_relationship_condition($rrc_args)->{join_free_condition}
        }
        dbic_internal_catch {
          $unique_carper->(
            "Resolution of relationship '$rel' failed unexpectedly, "
          . 'please relay the following error and seek assistance via '
          . DBIx::Class::_ENV_::HELP_URL . ". Encountered error: $_"
          );

          # FIXME - this is questionable
          # force skipping re-resolution, and instead just return an UC rset
          $relcond_is_freeform = 0;

          # RV
          undef;
        }
  );

  my $rel_rset;

  if( defined $jfc ) {

    $rel_rset = $rsrc->related_source($rel)->resultset->search_rs(
      $jfc,
      $rel_info->{attrs},
    );
  }
  elsif( $relcond_is_freeform ) {

    # A WHOREIFFIC hack to reinvoke the entire condition resolution
    # with the correct alias. Another way of doing this involves a
    # lot of state passing around, and the @_ positions are already
    # mapped out, making this crap a less icky option.
    #
    # The point of this exercise is to retain the spirit of the original
    # $obj->search_related($rel) where the resulting rset will have the
    # root alias as 'me', instead of $rel (as opposed to invoking
    # $rs->search_related)

    # make the fake 'me' rel
    local $rsrc->{_relationships}{me} = {
      %{ $rsrc->{_relationships}{$rel} },
      _original_name => $rel,
    };

    my $obj_table_alias = lc($rsrc->source_name) . '__row';
    $obj_table_alias =~ s/\W+/_/g;

    $rel_rset = $rsrc->resultset->search_rs(
      $self->ident_condition($obj_table_alias),
      { alias => $obj_table_alias },
    )->related_resultset('me')->search_rs(undef, $rel_info->{attrs})
  }
  else {

    my $attrs = { %{$rel_info->{attrs}} };
    my $reverse = $rsrc->reverse_relationship_info($rel);

    # FIXME - this loop doesn't seem correct - got to figure out
    # at some point what exactly it does.
    # See also the FIXME at the end of new_related()
    ( ( $reverse->{$_}{attrs}{accessor}||'') eq 'multi' )
      ? weaken( $attrs->{related_objects}{$_}[0] = $self )
      : weaken( $attrs->{related_objects}{$_}    = $self )
    for keys %$reverse;

    $rel_rset = $rsrc->related_source($rel)->resultset->search_rs(
      UNRESOLVABLE_CONDITION, # guards potential use of the $rs in the future
      $attrs,
    );
  }

  $self->{related_resultsets}{$rel} = $rel_rset;
}

=head2 search_related

=over 4

=item Arguments: $rel_name, $cond?, L<\%attrs?|DBIx::Class::ResultSet/ATTRIBUTES>

=item Return Value: L<$resultset|DBIx::Class::ResultSet> (scalar context) | L<@result_objs|DBIx::Class::Manual::ResultClass> (list context)

=back

Run a search on a related resultset. The search will be restricted to the
results represented by the L<DBIx::Class::ResultSet> it was called
upon.

See L<DBIx::Class::ResultSet/search_related> for more information.

=cut

sub search_related :DBIC_method_is_indirect_sugar {
  DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and fail_on_internal_call;
  shift->related_resultset(shift)->search(@_);
}

=head2 search_related_rs

This method works exactly the same as search_related, except that
it guarantees a resultset, even in list context.

=cut

sub search_related_rs :DBIC_method_is_indirect_sugar {
  DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and fail_on_internal_call;
  shift->related_resultset(shift)->search_rs(@_)
}

=head2 count_related

=over 4

=item Arguments: $rel_name, $cond?, L<\%attrs?|DBIx::Class::ResultSet/ATTRIBUTES>

=item Return Value: $count

=back

Returns the count of all the rows in the related resultset, restricted by the
current result or where conditions.

=cut

sub count_related :DBIC_method_is_indirect_sugar {
  DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and fail_on_internal_call;
  shift->related_resultset(shift)->search_rs(@_)->count;
}

=head2 new_related

=over 4

=item Arguments: $rel_name, \%col_data

=item Return Value: L<$result|DBIx::Class::Manual::ResultClass>

=back

Create a new result object of the related foreign class.  It will magically set
any foreign key columns of the new object to the related primary key columns
of the source object for you.  The newly created result will not be saved into
your storage until you call L<DBIx::Class::Row/insert> on it.

=cut

sub new_related {
  my ($self, $rel, $data) = @_;

  $self->throw_exception(
    "Result object instantiation requires a hashref as argument"
  ) unless ref $data eq 'HASH';

  my $rsrc = $self->result_source;
  my $rel_rsrc = $rsrc->related_source($rel);

###
### This section deliberately does not rely on require_join_free_values,
### as quite often the resulting related object is useless without the
### contents of $data mixed in. Originally this code was part of
### resolve_relationship_condition() but given it has a single, very
### context-specific call-site it made no sense to expose it to end users.
###

  my $rel_resolution = $rsrc->resolve_relationship_condition (
    rel_name => $rel,
    self_result_object => $self,

    # In case we are *not* in_storage it is ok to treat failed resolution as an empty hash
    # This happens e.g. as a result of various in-memory related graph of objects
    require_join_free_condition => !! $self->in_storage,

    # dummy aliases with deliberately known lengths, so that we can
    # quickly strip them below if needed
    foreign_alias => 'F',
    self_alias    => 'S',
  );

  my $rel_values =
    $rel_resolution->{join_free_values}
      ||
    { map { substr( $_, 2 ) => $rel_resolution->{join_free_condition}{$_} } keys %{ $rel_resolution->{join_free_condition} } }
  ;

  # mix everything together
  my $amalgamated_values = {
    %{
      # in case we got back join_free_values - they already have passed the extractor
      $rel_resolution->{join_free_values}
        ? $rel_values
        : extract_equality_conditions(
          $rel_values,
          'consider_nulls'
        )
    },
    %$data,
  };

  # cleanup possible rogue { somecolumn => [ -and => 1,2 ] }
  ($amalgamated_values->{$_}||'') eq UNRESOLVABLE_CONDITION
    and
  delete $amalgamated_values->{$_}
    for keys %$amalgamated_values;

  if( my @nonvalues = grep { ! exists $amalgamated_values->{$_} } keys %$rel_values ) {

    $self->throw_exception(
      "Unable to complete value inferrence - relationship '$rel' "
    . "on source '@{[ $rsrc->source_name ]}' results "
    . 'in expression(s) instead of definitive values: '
    . do {
        # FIXME - used for diag only, but still icky
        my $sqlm =
          dbic_internal_try { $rsrc->schema->storage->sql_maker }
            ||
          (
            require DBIx::Class::SQLMaker
              and
            DBIx::Class::SQLMaker->new
          )
        ;
        local $sqlm->{quote_char};
        local $sqlm->{_dequalify_idents} = 1;
        ($sqlm->_recurse_where({ map { $_ => $rel_values->{$_} } @nonvalues }))[0]
      }
    );
  }

  # And more complications - in case the relationship did not resolve
  # we *have* to loop things through search_related ( essentially re-resolving
  # everything we did so far, but with different type of handholding )
  # FIXME - this is still a mess, just a *little* better than it was
  # See also the FIXME at the end of related_resultset()
  exists $rel_resolution->{join_free_values}
    ? $rel_rsrc->result_class->new({ -result_source => $rel_rsrc, %$amalgamated_values })
    : $self->related_resultset($rel)->new_result( $amalgamated_values )
  ;
}

=head2 create_related

=over 4

=item Arguments: $rel_name, \%col_data

=item Return Value: L<$result|DBIx::Class::Manual::ResultClass>

=back

  my $result = $obj->create_related($rel_name, \%col_data);

Creates a new result object, similarly to new_related, and also inserts the
result's data into your storage medium. See the distinction between C<create>
and C<new> in L<DBIx::Class::ResultSet> for details.

=cut

sub create_related {
  my $self = shift;
  my $rel = shift;
  my $obj = $self->new_related($rel, @_)->insert;
  delete $self->{related_resultsets}->{$rel};
  return $obj;
}

=head2 find_related

=over 4

=item Arguments: $rel_name, \%col_data | @pk_values, { key => $unique_constraint, L<%attrs|DBIx::Class::ResultSet/ATTRIBUTES> }?

=item Return Value: L<$result|DBIx::Class::Manual::ResultClass> | undef

=back

  my $result = $obj->find_related($rel_name, \%col_data);

Attempt to find a related object using its primary key or unique constraints.
See L<DBIx::Class::ResultSet/find> for details.

=cut

sub find_related :DBIC_method_is_indirect_sugar {
  #my ($self, $rel, @args) = @_;
  DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and fail_on_internal_call;
  return shift->related_resultset(shift)->find(@_);
}

=head2 find_or_new_related

=over 4

=item Arguments: $rel_name, \%col_data, { key => $unique_constraint, L<%attrs|DBIx::Class::ResultSet/ATTRIBUTES> }?

=item Return Value: L<$result|DBIx::Class::Manual::ResultClass>

=back

Find a result object of a related class.  See L<DBIx::Class::ResultSet/find_or_new>
for details.

=cut

sub find_or_new_related {
  my $self = shift;
  my $rel = shift;
  my $obj = $self->related_resultset($rel)->find(@_);
  return defined $obj ? $obj : $self->related_resultset($rel)->new_result(@_);
}

=head2 find_or_create_related

=over 4

=item Arguments: $rel_name, \%col_data, { key => $unique_constraint, L<%attrs|DBIx::Class::ResultSet/ATTRIBUTES> }?

=item Return Value: L<$result|DBIx::Class::Manual::ResultClass>

=back

Find or create a result object of a related class. See
L<DBIx::Class::ResultSet/find_or_create> for details.

=cut

sub find_or_create_related {
  my $self = shift;
  my $rel = shift;
  my $obj = $self->related_resultset($rel)->find(@_);
  return (defined($obj) ? $obj : $self->create_related( $rel => @_ ));
}

=head2 update_or_create_related

=over 4

=item Arguments: $rel_name, \%col_data, { key => $unique_constraint, L<%attrs|DBIx::Class::ResultSet/ATTRIBUTES> }?

=item Return Value: L<$result|DBIx::Class::Manual::ResultClass>

=back

Update or create a result object of a related class. See
L<DBIx::Class::ResultSet/update_or_create> for details.

=cut

sub update_or_create_related :DBIC_method_is_indirect_sugar {
  #my ($self, $rel, @args) = @_;
  DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and fail_on_internal_call;
  shift->related_resultset(shift)->update_or_create(@_);
}

=head2 set_from_related

=over 4

=item Arguments: $rel_name, L<$result|DBIx::Class::Manual::ResultClass>

=item Return Value: not defined

=back

  $book->set_from_related('author', $author_obj);
  $book->author($author_obj);                      ## same thing

Set column values on the current object, using related values from the given
related object. This is used to associate previously separate objects, for
example, to set the correct author for a book, find the Author object, then
call set_from_related on the book.

This is called internally when you pass existing objects as values to
L<DBIx::Class::ResultSet/create>, or pass an object to a belongs_to accessor.

The columns are only set in the local copy of the object, call
L<update|DBIx::Class::Row/update> to update them in the storage.

=cut

sub set_from_related {
  my ($self, $rel, $f_obj) = @_;

  $self->set_columns( $self->result_source->resolve_relationship_condition (
    require_join_free_values => 1,
    rel_name => $rel,
    foreign_values => (
      # maintain crazy set_from_related interface
      #
      ( ! defined $f_obj )          ? +{}
    : ( ! defined blessed $f_obj )  ? $f_obj
                                    : do {

        my $f_result_class = $self->result_source->related_source($rel)->result_class;

        unless( $f_obj->isa($f_result_class) ) {

          $self->throw_exception(
            'Object supplied to set_from_related() must inherit from '
          . "'$DBIx::Class::ResultSource::__expected_result_class_isa'"
          ) unless $f_obj->isa(
            $DBIx::Class::ResultSource::__expected_result_class_isa
          );

          carp_unique(
            'Object supplied to set_from_related() usually should inherit from '
          . "the related ResultClass ('$f_result_class'), perhaps you've made "
          . 'a mistake?'
          );
        }

        +{ $f_obj->get_columns };
      }
    ),

    # an API where these are optional would be too cumbersome,
    # instead always pass in some dummy values
    DUMMY_ALIASPAIR,

  )->{join_free_values} );

  return 1;
}

=head2 update_from_related

=over 4

=item Arguments: $rel_name, L<$result|DBIx::Class::Manual::ResultClass>

=item Return Value: not defined

=back

  $book->update_from_related('author', $author_obj);

The same as L</"set_from_related">, but the changes are immediately updated
in storage.

=cut

sub update_from_related {
  my $self = shift;
  $self->set_from_related(@_);
  $self->update;
}

=head2 delete_related

=over 4

=item Arguments: $rel_name, $cond?, L<\%attrs?|DBIx::Class::ResultSet/ATTRIBUTES>

=item Return Value: $underlying_storage_rv

=back

Delete any related row, subject to the given conditions.  Internally, this
calls:

  $self->search_related(@_)->delete

And returns the result of that.

=cut

sub delete_related {
  my $self = shift;
  my $rel = shift;
  my $obj = $self->related_resultset($rel)->search_rs(@_)->delete;
  delete $self->{related_resultsets}->{$rel};
  return $obj;
}

=head2 add_to_$rel

B<Currently only available for C<has_many>, C<many_to_many> and 'multi' type
relationships.>

=head3 has_many / multi

=over 4

=item Arguments: \%col_data

=item Return Value: L<$result|DBIx::Class::Manual::ResultClass>

=back

Creates/inserts a new result object.  Internally, this calls:

  $self->create_related($rel, @_)

And returns the result of that.

=head3 many_to_many

=over 4

=item Arguments: (\%col_data | L<$result|DBIx::Class::Manual::ResultClass>), \%link_col_data?

=item Return Value: L<$result|DBIx::Class::Manual::ResultClass>

=back

  my $role = $schema->resultset('Role')->find(1);
  $actor->add_to_roles($role);
      # creates a My::DBIC::Schema::ActorRoles linking table result object

  $actor->add_to_roles({ name => 'lead' }, { salary => 15_000_000 });
      # creates a new My::DBIC::Schema::Role result object and the linking table
      # object with an extra column in the link

Adds a linking table object. If the first argument is a hash reference, the
related object is created first with the column values in the hash. If an object
reference is given, just the linking table object is created. In either case,
any additional column values for the linking table object can be specified in
C<\%link_col_data>.

See L<DBIx::Class::Relationship/many_to_many> for additional details.

=head2 set_$rel

B<Currently only available for C<many_to_many> relationships.>

=over 4

=item Arguments: (\@hashrefs_of_col_data | L<\@result_objs|DBIx::Class::Manual::ResultClass>), $link_vals?

=item Return Value: not defined

=back

  my $actor = $schema->resultset('Actor')->find(1);
  my @roles = $schema->resultset('Role')->search({ role =>
     { '-in' => ['Fred', 'Barney'] } } );

  $actor->set_roles(\@roles);
     # Replaces all of $actor's previous roles with the two named

  $actor->set_roles(\@roles, { salary => 15_000_000 });
     # Sets a column in the link table for all roles


Replace all the related objects with the given reference to a list of
objects. This does a C<delete> B<on the link table resultset> to remove the
association between the current object and all related objects, then calls
C<add_to_$rel> repeatedly to link all the new objects.

Note that this means that this method will B<not> delete any objects in the
table on the right side of the relation, merely that it will delete the link
between them.

Due to a mistake in the original implementation of this method, it will also
accept a list of objects or hash references. This is B<deprecated> and will be
removed in a future version.

=head2 remove_from_$rel

B<Currently only available for C<many_to_many> relationships.>

=over 4

=item Arguments: L<$result|DBIx::Class::Manual::ResultClass>

=item Return Value: not defined

=back

  my $role = $schema->resultset('Role')->find(1);
  $actor->remove_from_roles($role);
      # removes $role's My::DBIC::Schema::ActorRoles linking table result object

Removes the link between the current object and the related object. Note that
the related object itself won't be deleted unless you call ->delete() on
it. This method just removes the link between the two objects.

=head1 FURTHER QUESTIONS?

Check the list of L<additional DBIC resources|DBIx::Class/GETTING HELP/SUPPORT>.

=head1 COPYRIGHT AND LICENSE

This module is free software L<copyright|DBIx::Class/COPYRIGHT AND LICENSE>
by the L<DBIx::Class (DBIC) authors|DBIx::Class/AUTHORS>. You can
redistribute it and/or modify it under the same terms as the
L<DBIx::Class library|DBIx::Class/COPYRIGHT AND LICENSE>.

=cut

1;
