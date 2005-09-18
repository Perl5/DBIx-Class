package DBIx::Class::Relationship;

use strict;
use warnings;

use base qw/DBIx::Class Class::Data::Inheritable/;

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
model. It allows your to set up relationships, and to perform joins
on searches.

This POD details only the convenience methods for setting up standard
relationship types. For more information see ::Relationship::Base

=head1 METHODS

All convenience methods take a signature of the following format -

  __PACKAGE__>method_name('relname', 'Foreign::Class', $join?, $attrs?);



=over 4

=item has_one

  my $f_obj = $obj->relname;

Creates a one-one relationship with another class; defaults to PK-PK for
the join condition unless a condition is specified.

=item might_have

  my $f_obj = $obj->relname;

Creates an optional one-one relationship with another class; defaults to PK-PK
for the join condition unless a condition is specified.

=item has_many

  my @f_obj = $obj->relname($cond?, $attrs?);
  my $f_result_set = $obj->relname($cond?, $attrs?);

  $obj->add_to_relname(\%col_data);

Creates a one-many relationship with another class; 

=item belongs_to

  my $f_obj = $obj->relname;

  $obj->relname($new_f_obj);

Creates a relationship where we store the foreign class' PK; if $join is a
column name instead of a condition that is assumed to be the FK, if not
has_many assumes the FK is the relname is that is a column on the current
class.

=cut

1;

=back

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

