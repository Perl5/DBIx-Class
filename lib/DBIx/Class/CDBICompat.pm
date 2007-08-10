package DBIx::Class::CDBICompat;

use strict;
use warnings;
use base qw/DBIx::Class::Core DBIx::Class::DB/;
use Carp::Clan qw/^DBIx::Class/;

eval {
  require Class::Trigger;
  require DBIx::ContextualFetch;
};
croak "Class::Trigger and DBIx::ContextualFetch is required for CDBICompat" if $@;

__PACKAGE__->load_own_components(qw/
  Constraints
  Triggers
  ReadOnly
  LiveObjectIndex
  AttributeAPI
  Stringify
  DestroyWarning
  Constructor
  AccessorMapping
  ColumnCase
  HasA
  HasMany
  MightHave
  Copy
  LazyLoading
  AutoUpdate
  TempColumns
  GetSet
  Retrieve
  Pager
  ColumnGroups
  AbstractSearch
  ImaDBI
  Iterator
/);

            #DBIx::Class::ObjIndexStubs
1;

=head1 NAME

DBIx::Class::CDBICompat - Class::DBI Compatibility layer.

=head1 SYNOPSIS

  use base qw/DBIx::Class/;
  __PACKAGE__->load_components(qw/CDBICompat Core DB/);

=head1 DESCRIPTION

DBIx::Class features a fully featured compatibility layer with L<Class::DBI>
and L<Class::DBI::AbstractSearch> to ease transition for existing CDBI users. 

In fact, this class is just a receipe containing all the features emulated.
If you like, you can choose which features to emulate by building your 
own class and loading it like this:

  __PACKAGE__->load_own_components(qw/CDBICompat/);

this will automatically load the features included in My::DB::CDBICompat,
provided it looks something like this:

  package My::DB::CDBICompat;
  __PACKAGE__->load_components(qw/
    CDBICompat::ColumnGroups
    CDBICompat::Retrieve
    CDBICompat::HasA
    CDBICompat::HasMany
    CDBICompat::MightHave
  /);

=head1 COMPONENTS

=over 4

=item AccessorMapping

=item AbstractSearch

Compatibility with Class::DBI::AbstractSearch.

=item AttributeAPI

=item AutoUpdate

Allows you to turn on automatic updates for column values.

=item ColumnCase

=item ColumnGroups

=item Constraints

=item Constructor

=item DestroyWarning

=item GetSet

=item HasA

=item HasMany

=item ImaDBI

=item LazyLoading

=item LiveObjectIndex

The live object index tries to ensure there is only one version of a object
in the perl interpreter.

=item MightHave

=item ObjIndexStubs

=item ReadOnly

=item Retrieve

=item Stringify

=item TempColumns

=item Triggers

=item PassThrough

=back

=head1 LIMITATIONS

The following methods and classes are not emulated, maybe in the future.

=over 4

=item Class::DBI::Query

Deprecated in Class::DBI.

=item Class::DBI::Column

Not documented in Class::DBI.  CDBICompat's columns() returns a plain string, not an object.

=item data_type()

Undocumented CDBI method.

=item meta_info()

Undocumented CDBI method.

=back

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

