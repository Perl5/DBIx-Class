package DBIx::Class::Relationship::Base;

use strict;
use warnings;

use base qw/DBIx::Class/;

use Scalar::Util qw/weaken blessed/;
use Try::Tiny;
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

=item Arguments: 'relname', 'Foreign::Class', $condition, $attrs

=back

  __PACKAGE__->add_relationship('relname',
                                'Foreign::Class',
                                $condition, $attrs);

Create a custom relationship between one result source and another
source, indicated by its class name.

=head3 condition

The condition argument describes the C<ON> clause of the C<JOIN>
expression used to connect the two sources when creating SQL queries.

To create simple equality joins, supply a hashref containing the
remote table column name as the key(s), and the local table column
name as the value(s), for example given:

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

C<foreign> and C<self> are pseudo aliases and must be entered
literally. They will be replaced with the actual correct table alias
when the SQL is produced.

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

As is the default in L<SQL::Abstract>, the key-value pairs will be
C<AND>ed in the result. C<OR> can be achieved with an arrayref, for
example a condition like:

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
elect to additionally return a simplified join-free condition hashref when
invoked as C<< $row_object->relationship >>, as opposed to
C<< $rs->related_resultset('relationship') >>. In this case C<$row_object> is
passed to the coderef as C<< $args->{self_rowobj} >>, so a user can do the
following:

  sub {
    my $args = shift;

    return (
      {
        "$args->{foreign_alias}.artist" => { -ident => "$args->{self_alias}.artistid" },
        "$args->{foreign_alias}.year"   => { '>', "1979", '<', "1990" },
      },
      $args->{self_rowobj} && {
        "$args->{foreign_alias}.artist" => $args->{self_rowobj}->artistid,
        "$args->{foreign_alias}.year"   => { '>', "1979", '<', "1990" },
      },
    );
  }

Now this code:

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

Note that in order to be able to use
L<< $row->create_related|DBIx::Class::Relationship::Base/create_related >>,
the coderef must not only return as its second such a "simple" condition
hashref which does not depend on joins being available, but the hashref must
contain only plain values/deflatable objects, such that the result can be
passed directly to L<DBIx::Class::Relationship::Base/set_from_related>. For
instance the C<year> constraint in the above example prevents the relationship
from being used to to create related objects (an exception will be thrown).

In order to allow the user to go truly crazy when generating a custom C<ON>
clause, the C<$args> hashref passed to the subroutine contains some extra
metadata. Currently the supplied coderef is executed as:

  $relationship_info->{cond}->({
    self_alias        => The alias of the invoking resultset ('me' in case of a row object),
    foreign_alias     => The alias of the to-be-joined resultset (often matches relname),
    self_resultsource => The invocant's resultsource,
    foreign_relname   => The relationship name (does *not* always match foreign_alias),
    self_rowobj       => The invocant itself in case of $row_obj->relationship
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

=item \%column

A hashref where each key is the accessor you want installed in the main class,
and its value is the name of the original in the fireign class.

  MyApp::Schema::Track->belongs_to( cd => 'DBICTest::Schema::CD', 'cd', {
      proxy => { cd_title => 'title' },
  });

This will create an accessor named C<cd_title> on the C<$track> row object.

=back

NOTE: you can pass a nested struct too, for example:

  MyApp::Schema::Track->belongs_to( cd => 'DBICTest::Schema::CD', 'cd', {
    proxy => [ 'year', { cd_title => 'title' } ],
  });

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

=item Arguments: $relname, $rel_info

=back

Registers a relationship on the class. This is called internally by
DBIx::Class::ResultSourceProxy to set up Accessors and Proxies.

=cut

sub register_relationship { }

=head2 related_resultset

=over 4

=item Arguments: $relationship_name

=item Return Value: $related_resultset

=back

  $rs = $cd->related_resultset('artist');

Returns a L<DBIx::Class::ResultSet> for the relationship named
$relationship_name.

=cut

sub related_resultset {
  my $self = shift;
  $self->throw_exception("Can't call *_related as class methods")
    unless ref $self;
  my $rel = shift;
  my $rel_info = $self->relationship_info($rel);
  $self->throw_exception( "No such relationship ${rel}" )
    unless $rel_info;

  return $self->{related_resultsets}{$rel} ||= do {
    my $attrs = (@_ > 1 && ref $_[$#_] eq 'HASH' ? pop(@_) : {});
    $attrs = { %{$rel_info->{attrs} || {}}, %$attrs };

    $self->throw_exception( "Invalid query: @_" )
      if (@_ > 1 && (@_ % 2 == 1));
    my $query = ((@_ > 1) ? {@_} : shift);

    my $source = $self->result_source;

    # condition resolution may fail if an incomplete master-object prefetch
    # is encountered - that is ok during prefetch construction (not yet in_storage)
    my ($cond, $is_crosstable) = try {
      $source->_resolve_condition( $rel_info->{cond}, $rel, $self, $rel )
    }
    catch {
      if ($self->in_storage) {
        $self->throw_exception ($_);
      }

      $DBIx::Class::ResultSource::UNRESOLVABLE_CONDITION;  # RV
    };

    # keep in mind that the following if() block is part of a do{} - no return()s!!!
    if ($is_crosstable) {
      $self->throw_exception (
        "A cross-table relationship condition returned for statically declared '$rel'")
          unless ref $rel_info->{cond} eq 'CODE';

      # A WHOREIFFIC hack to reinvoke the entire condition resolution
      # with the correct alias. Another way of doing this involves a
      # lot of state passing around, and the @_ positions are already
      # mapped out, making this crap a less icky option.
      #
      # The point of this exercise is to retain the spirit of the original
      # $obj->search_related($rel) where the resulting rset will have the
      # root alias as 'me', instead of $rel (as opposed to invoking
      # $rs->search_related)

      local $source->{_relationships}{me} = $source->{_relationships}{$rel};  # make the fake 'me' rel
      my $obj_table_alias = lc($source->source_name) . '__row';
      $obj_table_alias =~ s/\W+/_/g;

      $source->resultset->search(
        $self->ident_condition($obj_table_alias),
        { alias => $obj_table_alias },
      )->search_related('me', $query, $attrs)
    }
    else {
      # FIXME - this conditional doesn't seem correct - got to figure out
      # at some point what it does. Also the entire UNRESOLVABLE_CONDITION
      # business seems shady - we could simply not query *at all*
      if ($cond eq $DBIx::Class::ResultSource::UNRESOLVABLE_CONDITION) {
        my $reverse = $source->reverse_relationship_info($rel);
        foreach my $rev_rel (keys %$reverse) {
          if ($reverse->{$rev_rel}{attrs}{accessor} && $reverse->{$rev_rel}{attrs}{accessor} eq 'multi') {
            weaken($attrs->{related_objects}{$rev_rel}[0] = $self);
          } else {
            weaken($attrs->{related_objects}{$rev_rel} = $self);
          }
        }
      }
      elsif (ref $cond eq 'ARRAY') {
        $cond = [ map {
          if (ref $_ eq 'HASH') {
            my $hash;
            foreach my $key (keys %$_) {
              my $newkey = $key !~ /\./ ? "me.$key" : $key;
              $hash->{$newkey} = $_->{$key};
            }
            $hash;
          } else {
            $_;
          }
        } @$cond ];
      }
      elsif (ref $cond eq 'HASH') {
       foreach my $key (grep { ! /\./ } keys %$cond) {
          $cond->{"me.$key"} = delete $cond->{$key};
        }
      }

      $query = ($query ? { '-and' => [ $cond, $query ] } : $cond);
      $self->result_source->related_source($rel)->resultset->search(
        $query, $attrs
      );
    }
  };
}

=head2 search_related

  @objects = $rs->search_related('relname', $cond, $attrs);
  $objects_rs = $rs->search_related('relname', $cond, $attrs);

Run a search on a related resultset. The search will be restricted to the
item or items represented by the L<DBIx::Class::ResultSet> it was called
upon. This method can be called on a ResultSet, a Row or a ResultSource class.

=cut

sub search_related {
  return shift->related_resultset(shift)->search(@_);
}

=head2 search_related_rs

  ( $objects_rs ) = $rs->search_related_rs('relname', $cond, $attrs);

This method works exactly the same as search_related, except that
it guarantees a resultset, even in list context.

=cut

sub search_related_rs {
  return shift->related_resultset(shift)->search_rs(@_);
}

=head2 count_related

  $obj->count_related('relname', $cond, $attrs);

Returns the count of all the items in the related resultset, restricted by the
current item or where conditions. Can be called on a
L<DBIx::Class::Manual::Glossary/"ResultSet"> or a
L<DBIx::Class::Manual::Glossary/"Row"> object.

=cut

sub count_related {
  my $self = shift;
  return $self->search_related(@_)->count;
}

=head2 new_related

  my $new_obj = $obj->new_related('relname', \%col_data);

Create a new item of the related foreign class. If called on a
L<Row|DBIx::Class::Manual::Glossary/"Row"> object, it will magically
set any foreign key columns of the new object to the related primary
key columns of the source object for you.  The newly created item will
not be saved into your storage until you call L<DBIx::Class::Row/insert>
on it.

=cut

sub new_related {
  my ($self, $rel, $values, $attrs) = @_;

  # FIXME - this is a bad position for this (also an identical copy in
  # set_from_related), but I have no saner way to hook, and I absolutely
  # want this to throw at least for coderefs, instead of the "insert a NULL
  # when it gets hard" insanity --ribasushi
  #
  # sanity check - currently throw when a complex coderef rel is encountered
  # FIXME - should THROW MOAR!

  if (ref $self) {  # cdbi calls this as a class method, /me vomits

    my $rsrc = $self->result_source;
    my (undef, $crosstable, $relcols) = $rsrc->_resolve_condition (
      $rsrc->relationship_info($rel)->{cond}, $rel, $self, $rel
    );

    $self->throw_exception("Custom relationship '$rel' does not resolve to a join-free condition fragment")
      if $crosstable;

    if (@{$relcols || []} and @$relcols = grep { ! exists $values->{$_} } @$relcols) {
      $self->throw_exception(sprintf (
        "Custom relationship '%s' not definitive - returns conditions instead of values for column(s): %s",
        $rel,
        map { "'$_'" } @$relcols
      ));
    }
  }

  my $row = $self->search_related($rel)->new($values, $attrs);
  return $row;
}

=head2 create_related

  my $new_obj = $obj->create_related('relname', \%col_data);

Creates a new item, similarly to new_related, and also inserts the item's data
into your storage medium. See the distinction between C<create> and C<new>
in L<DBIx::Class::ResultSet> for details.

=cut

sub create_related {
  my $self = shift;
  my $rel = shift;
  my $obj = $self->new_related($rel, @_)->insert;
  delete $self->{related_resultsets}->{$rel};
  return $obj;
}

=head2 find_related

  my $found_item = $obj->find_related('relname', @pri_vals | \%pri_vals);

Attempt to find a related object using its primary key or unique constraints.
See L<DBIx::Class::ResultSet/find> for details.

=cut

sub find_related {
  my $self = shift;
  my $rel = shift;
  return $self->search_related($rel)->find(@_);
}

=head2 find_or_new_related

  my $new_obj = $obj->find_or_new_related('relname', \%col_data);

Find an item of a related class. If none exists, instantiate a new item of the
related class. The object will not be saved into your storage until you call
L<DBIx::Class::Row/insert> on it.

=cut

sub find_or_new_related {
  my $self = shift;
  my $obj = $self->find_related(@_);
  return defined $obj ? $obj : $self->new_related(@_);
}

=head2 find_or_create_related

  my $new_obj = $obj->find_or_create_related('relname', \%col_data);

Find or create an item of a related class. See
L<DBIx::Class::ResultSet/find_or_create> for details.

=cut

sub find_or_create_related {
  my $self = shift;
  my $obj = $self->find_related(@_);
  return (defined($obj) ? $obj : $self->create_related(@_));
}

=head2 update_or_create_related

  my $updated_item = $obj->update_or_create_related('relname', \%col_data, \%attrs?);

Update or create an item of a related class. See
L<DBIx::Class::ResultSet/update_or_create> for details.

=cut

sub update_or_create_related {
  my $self = shift;
  my $rel = shift;
  return $self->related_resultset($rel)->update_or_create(@_);
}

=head2 set_from_related

  $book->set_from_related('author', $author_obj);
  $book->author($author_obj);                      ## same thing

Set column values on the current object, using related values from the given
related object. This is used to associate previously separate objects, for
example, to set the correct author for a book, find the Author object, then
call set_from_related on the book.

This is called internally when you pass existing objects as values to
L<DBIx::Class::ResultSet/create>, or pass an object to a belongs_to accessor.

The columns are only set in the local copy of the object, call L</update> to
set them in the storage.

=cut

sub set_from_related {
  my ($self, $rel, $f_obj) = @_;

  my $rsrc = $self->result_source;
  my $rel_info = $rsrc->relationship_info($rel)
    or $self->throw_exception( "No such relationship ${rel}" );

  if (defined $f_obj) {
    my $f_class = $rel_info->{class};
    $self->throw_exception( "Object $f_obj isn't a ".$f_class )
      unless blessed $f_obj and $f_obj->isa($f_class);
  }


  # FIXME - this is a bad position for this (also an identical copy in
  # new_related), but I have no saner way to hook, and I absolutely
  # want this to throw at least for coderefs, instead of the "insert a NULL
  # when it gets hard" insanity --ribasushi
  #
  # sanity check - currently throw when a complex coderef rel is encountered
  # FIXME - should THROW MOAR!
  my ($cond, $crosstable, $relcols) = $rsrc->_resolve_condition (
    $rel_info->{cond}, $f_obj, $rel, $rel
  );
  $self->throw_exception("Custom relationship '$rel' does not resolve to a join-free condition fragment")
    if $crosstable;
  $self->throw_exception(sprintf (
    "Custom relationship '%s' not definitive - returns conditions instead of values for column(s): %s",
    $rel,
    map { "'$_'" } @$relcols
  )) if @{$relcols || []};

  $self->set_columns($cond);

  return 1;
}

=head2 update_from_related

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

  $obj->delete_related('relname', $cond, $attrs);

Delete any related item subject to the given conditions.

=cut

sub delete_related {
  my $self = shift;
  my $obj = $self->search_related(@_)->delete;
  delete $self->{related_resultsets}->{$_[0]};
  return $obj;
}

=head2 add_to_$rel

B<Currently only available for C<has_many>, C<many-to-many> and 'multi' type
relationships.>

=over 4

=item Arguments: ($foreign_vals | $obj), $link_vals?

=back

  my $role = $schema->resultset('Role')->find(1);
  $actor->add_to_roles($role);
      # creates a My::DBIC::Schema::ActorRoles linking table row object

  $actor->add_to_roles({ name => 'lead' }, { salary => 15_000_000 });
      # creates a new My::DBIC::Schema::Role row object and the linking table
      # object with an extra column in the link

Adds a linking table object for C<$obj> or C<$foreign_vals>. If the first
argument is a hash reference, the related object is created first with the
column values in the hash. If an object reference is given, just the linking
table object is created. In either case, any additional column values for the
linking table object can be specified in C<$link_vals>.

=head2 set_$rel

B<Currently only available for C<many-to-many> relationships.>

=over 4

=item Arguments: (\@hashrefs | \@objs), $link_vals?

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

B<Currently only available for C<many-to-many> relationships.>

=over 4

=item Arguments: $obj

=back

  my $role = $schema->resultset('Role')->find(1);
  $actor->remove_from_roles($role);
      # removes $role's My::DBIC::Schema::ActorRoles linking table row object

Removes the link between the current object and the related object. Note that
the related object itself won't be deleted unless you call ->delete() on
it. This method just removes the link between the two objects.

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
