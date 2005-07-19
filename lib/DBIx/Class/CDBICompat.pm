package DBIx::Class::CDBICompat;

use strict;
use warnings;

use base qw/DBIx::Class::CDBICompat::Convenience
            DBIx::Class::CDBICompat::Stringify
            DBIx::Class::CDBICompat::ObjIndexStubs
            DBIx::Class::CDBICompat::DestroyWarning
            DBIx::Class::CDBICompat::Constructor
            DBIx::Class::CDBICompat::AutoUpdate
            DBIx::Class::CDBICompat::AccessorMapping
            DBIx::Class::CDBICompat::ColumnCase
            DBIx::Class::CDBICompat::ColumnGroups
            DBIx::Class::CDBICompat::ImaDBI/;

1;
