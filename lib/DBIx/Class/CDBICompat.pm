package DBIx::Class::CDBICompat;

use strict;
use warnings;
use base qw/DBIx::Class/;

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
  MightHave
  HasMany
  HasA
  LazyLoading
  AutoUpdate
  TempColumns
  Retrieve
  ColumnGroups
  ImaDBI/);

            #DBIx::Class::ObjIndexStubs
1;

=head1 NAME 

DBIx::Class::CDBICompat - Class::DBI Compatability layer.

=head1 DESCRIPTION

This class just inherits from the various modules that makes 
up the Class::DBI compability layer.


=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

