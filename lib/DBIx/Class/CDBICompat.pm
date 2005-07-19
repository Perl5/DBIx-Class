package DBIx::Class::CDBICompat;

use strict;
use warnings;

use base qw/DBIx::Class::CDBICompat::AccessorMapping
            DBIx::Class::CDBICompat::ColumnCase
            DBIx::Class::CDBICompat::ColumnGroups/;

1;
