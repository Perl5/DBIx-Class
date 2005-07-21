package DBIx::Class::Core;

use strict;
use warnings;

use base qw/DBIx::Class::PK
            DBIx::Class::Table
            DBIx::Class::SQL
            DBIx::Class::DB
            DBIx::Class::AccessorGroup/;

1;
