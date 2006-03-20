package DBIx::Class::Relationship;

use strict;
use warnings;

use base qw/DBIx::Class/;

__PACKAGE__->load_own_components(qw/
  Helpers
  Accessor
  CascadeActions
  ProxyMethods
  Base
/);

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

  # in a Book class (where Author has many Books)
  My::DBIC::Schema::Book->belongs_to(author => 'Author');
  my $author_obj = $obj->author;
  $obj->author($new_author_obj);

Creates a relationship where the calling class stores the foreign class's 
primary key in one (or more) of its columns. If $cond is a column name
instead of a join condition hash, that is used as the name of the column
holding the foreign key. If $cond is not given, the relname is used as
the column name.

NOTE: If you are used to L<Class::DBI> relationships, this is the equivalent
of C<has_a>.

=head2 has_many

  # in an Author class (where Author has many Books)
  My::DBIC::Schema::Author->has_many(books => 'Book', 'author');
  my $booklist = $obj->books;
  my $booklist = $obj->books({ name => { LIKE => '%macaroni%' }, { prefetch => [qw/book/] });
  my @book_objs = $obj->books;

  $obj->add_to_books(\%col_data);

Creates a one-to-many relationship, where the corresponding elements of the
foreign class store the calling class's primary key in one (or more) of its
columns. You should pass the name of the column in the foreign class as the
$cond argument, or specify a complete join condition.

If you delete an object in a class with a C<has_many> relationship, all
related objects will be deleted as well. However, any database-level
cascade or restrict will take precedence.

=head2 might_have

  My::DBIC::Schema::Author->might_have(psuedonym => 'Psuedonyms');
  my $pname = $obj->psuedonym; # to get the Psuedonym object

Creates an optional one-to-one relationship with a class, where the foreign
class stores our primary key in one of its columns. Defaults to the primary
key of the foreign class unless $cond specifies a column or join condition.

If you update or delete an object in a class with a C<might_have>
relationship, the related object will be updated or deleted as well.
Any database-level update or delete constraints will override this behaviour.

=head2 has_one

  My::DBIC::Schema::Book->has_one(isbn => ISBN);
  my $isbn_obj = $obj->isbn;

Creates a one-to-one relationship with another class. This is just like
C<might_have>, except the implication is that the other object is always
present. The only difference between C<has_one> and C<might_have> is that
C<has_one> uses an (ordinary) inner join, whereas C<might_have> uses a
left join.


=head2 many_to_many

  My::DBIC::Schema::Actor->many_to_many( roles => 'actor_roles', 'Roles' );
  my @role_objs = $obj_a->roles;

Creates an accessor bridging two relationships; not strictly a relationship
in its own right, although the accessor will return a resultset or collection
of objects just as a has_many would.

=cut

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

