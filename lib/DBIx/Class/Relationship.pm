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

  __PACKAGE__>method_name('relname', 'Foreign::Class', $cond, $attrs);
  
Both C<$cond> and C<$attrs> are optional. Pass C<undef> for C<$cond> if
you want to use the default value for it, but still want to set C<$attrs>.
The following attributes are recognize:

=head2 join_type

Explicitly specifies the type of join to use in the relationship. Any SQL
join type is valid, e.g. C<LEFT> or C<RIGHT>. It will be placed in the SQL
command immediately before C<JOIN>.

=head2 proxy

An arrayref containing a list of accessors in the foreign class to proxy in
the main class. If, for example, you do the following:
  
  __PACKAGE__->might_have(bar => 'Bar', undef, { proxy => qw[/ margle /] });
  
Then, assuming Bar has an accessor named margle, you can do:

  my $obj = Foo->find(1);
  $obj->margle(10); # set margle; Bar object is created if it doesn't exist

=head2 belongs_to

  my $f_obj = $obj->relname;

  $obj->relname($new_f_obj);

Creates a relationship where we store the foreign class' PK; if $join is a
column name instead of a condition that is assumed to be the FK, if not
has_many assumes the FK is the relname is that is a column on the current
class.

=head2 has_many

  my @f_obj = $obj->relname($cond?, $attrs?);
  my $f_result_set = $obj->relname($cond?, $attrs?);

  $obj->add_to_relname(\%col_data);

Creates a one-many relationship with another class; 

=head2 might_have

  my $f_obj = $obj->relname;

Creates an optional one-one relationship with another class; defaults to PK-PK
for the join condition unless a condition is specified.

=head2 has_one

  my $f_obj = $obj->relname;

Creates a one-one relationship with another class; defaults to PK-PK for
the join condition unless a condition is specified.

=cut

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

