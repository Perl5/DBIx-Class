package DBIx::Class::Relationship;

use strict;
use warnings;

use base qw/DBIx::Class/;

__PACKAGE__->load_own_components(qw/
  HasMany
  HasOne
  BelongsTo
  Accessor
  CascadeActions
  ProxyMethods
  Base
/);

__PACKAGE__->mk_classdata('_relationships', { } );

=head1 NAME 

DBIx::Class::Relationship - Inter-table relationships

=head1 SYNOPSIS

=head1 DESCRIPTION

This class handles relationships between the tables in your database
model. It allows you to set up relationships and perform joins on them.

Only the helper methods for setting up standard relationship types
are documented here. For the basic, lower-level methods, see
L<DBIx::Class::Relationship::Base>.

=head1 METHODS

All helper methods take the following arguments:

  __PACKAGE__>$method_name('relname', 'Foreign::Class', $cond, $attrs);
  
Both C<$cond> and C<$attrs> are optional. Pass C<undef> for C<$cond> if
you want to use the default value for it, but still want to set C<$attrs>.
See L<DBIx::Class::Relationship::Base> for a list of valid attributes.

=head2 belongs_to

  # in a Bar class (where Foo has many Bars)
  __PACKAGE__->belongs_to(foo => Foo);
  my $f_obj = $obj->foo;
  $obj->foo($new_f_obj);

Creates a relationship where the calling class stores the foreign class's 
primary key in one (or more) of its columns. If $cond is a column name
instead of a join condition hash, that is used as the name of the column
holding the foreign key. If $cond is not given, the relname is used as
the column name.

NOTE: If you are used to L<Class::DBI> relationships, this is the equivalent
of C<has_a>.

=head2 has_many

  # in a Foo class (where Foo has many Bars)
  __PACKAGE__->has_many(bar => Bar, 'foo');
  my $f_resultset = $obj->foo;
  my $f_resultset = $obj->foo({ name => { LIKE => '%macaroni%' }, { prefetch => [qw/bar/] });
  my @f_obj = $obj->foo;

  $obj->add_to_foo(\%col_data);

Creates a one-to-many relationship, where the corresponding elements of the
foreign class store the calling class's primary key in one (or more) of its
columns. You should pass the name of the column in the foreign class as the
$cond argument, or specify a complete join condition.

If you delete an object in a class with a C<has_many> relationship, all
related objects will be deleted as well. However, any database-level
cascade or restrict will take precedence.

=head2 might_have

  __PACKAGE__->might_have(baz => Baz);
  my $f_obj = $obj->baz; # to get the baz object

Creates an optional one-to-one relationship with a class, where the foreign class 
stores our primary key in one of its columns. Defaults to the primary key of the
foreign class unless $cond specifies a column or join condition.

If you update or delete an object in a class with a C<might_have> relationship, 
the related object will be updated or deleted as well. Any database-level update
or delete constraints will override this behavior.

=head2 has_one

  __PACKAGE__->has_one(gorch => Gorch);
  my $f_obj = $obj->gorch;

Creates a one-to-one relationship with another class. This is just like C<might_have>,
except the implication is that the other object is always present. The only different
between C<has_one> and C<might_have> is that C<has_one> uses an (ordinary) inner join,
whereas C<might_have> uses a left join.

=cut

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

