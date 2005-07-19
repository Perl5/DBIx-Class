package DBIx::Class::CDBICompat;

use strict;
use warnings;

use base qw/DBIx::Class::CDBICompat::Convenience
            DBIx::Class::CDBICompat::AccessorMapping
            DBIx::Class::CDBICompat::ColumnCase
            DBIx::Class::CDBICompat::ColumnGroups
            DBIx::Class::CDBICompat::ImaDBI/;

1;
