package DBIx::Class::Core;

use strict;
use warnings;

use base qw/DBIx::Class::Relationship
            DBIx::Class::SQL::OrderBy
            DBIx::Class::SQL::Abstract
            DBIx::Class::PK
            DBIx::Class::Table
            DBIx::Class::SQL
            DBIx::Class::DB
            DBIx::Class::AccessorGroup/;

1;
