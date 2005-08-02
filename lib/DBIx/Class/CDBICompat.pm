package DBIx::Class::CDBICompat;

use strict;
use warnings;

use base qw/DBIx::Class::CDBICompat::Constraints
            DBIx::Class::CDBICompat::Triggers
            DBIx::Class::CDBICompat::ReadOnly
            DBIx::Class::CDBICompat::GetSet
            DBIx::Class::CDBICompat::LiveObjectIndex
            DBIx::Class::CDBICompat::AttributeAPI
            DBIx::Class::CDBICompat::Stringify
            DBIx::Class::CDBICompat::DestroyWarning
            DBIx::Class::CDBICompat::Constructor
            DBIx::Class::CDBICompat::AccessorMapping
            DBIx::Class::CDBICompat::ColumnCase
            DBIx::Class::CDBICompat::MightHave
            DBIx::Class::CDBICompat::HasMany
            DBIx::Class::CDBICompat::HasA
            DBIx::Class::CDBICompat::LazyLoading
            DBIx::Class::CDBICompat::AutoUpdate
            DBIx::Class::CDBICompat::TempColumns
            DBIx::Class::CDBICompat::ColumnGroups
            DBIx::Class::CDBICompat::ImaDBI/;

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

