package DBIx::Class::CDBICompat;

use strict;
use warnings;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/
  CDBICompat::Constraints
  CDBICompat::Triggers
  CDBICompat::ReadOnly
  CDBICompat::GetSet
  CDBICompat::LiveObjectIndex
  CDBICompat::AttributeAPI
  CDBICompat::Stringify
  CDBICompat::DestroyWarning
  CDBICompat::Constructor
  CDBICompat::AccessorMapping
  CDBICompat::ColumnCase
  CDBICompat::MightHave
  CDBICompat::HasMany
  CDBICompat::HasA
  CDBICompat::LazyLoading
  CDBICompat::AutoUpdate
  CDBICompat::TempColumns
  CDBICompat::Retrieve
  CDBICompat::ColumnGroups
  CDBICompat::ImaDBI/);

            #DBIx::Class::CDBICompat::ObjIndexStubs
1;

=head1 NAME 

DBIx::Class::CDBICompat - Class::DBI Compatability layer.

=head1 DESCRIPTION

This class just inherits from the various modules that makes 
up the Class::DBI compability layer.


=head1 AUTHORS

Matt S. Trout <perl-stuff@trout.me.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

