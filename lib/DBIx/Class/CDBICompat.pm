package DBIx::Class::CDBICompat;

use strict;
use warnings;
use base qw/DBIx::Class::Core DBIx::Class::DB/;

__PACKAGE__->load_own_components(qw/
  Constraints
  Triggers
  ReadOnly
  GetSet
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
  LazyLoading
  AutoUpdate
  TempColumns
  Retrieve
  Pager
  ColumnGroups
  ImaDBI/);

            #DBIx::Class::ObjIndexStubs
1;

=head1 NAME 

DBIx::Class::CDBICompat - Class::DBI Compatability layer.

=head1 SYNOPSIS

  use base qw/DBIx::Class/;
  __PACKAGE__->load_components(qw/CDBICompat Core DB/);

=head1 DESCRIPTION

DBIx::Class features a fully featured compability layer with L<Class::DBI>
to ease transition for existing CDBI users. In fact, this class is just a
receipe containing all the features emulated. If you like, you can choose
which features to emulate by building your own class and loading it like 
this:

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

=head1 Components

=over 4

=item AccessorMapping

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

Responsible for HasA relationships. 

=item HasMany

Responsible for HasMany relationships. 

=item ImaDBI

=item LazyLoading

=item LiveObjectIndex

The live object index tries to ensure there is only one version of a object
in the perl interprenter.

=item MightHave

Responsible for MightHave relationships. 

=item ObjIndexStubs

=item ReadOnly

=item Retrieve

=item Stringify

=item TempColumns

=item Triggers

This class implements the trigger functionality.

=item PassThrough

=back

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

