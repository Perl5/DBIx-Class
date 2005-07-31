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
            DBIx::Class::Exception
            DBIx::Class::AccessorGroup/;

1;

=head1 NAME 

DBIx::Class::Core - Core set of DBIx::Class modules.

=head1 DESCRIPTION

This class just inherits from the various modules that makes 
up the Class::DBI  core features.


=head1 AUTHORS

Matt S. Trout <perl-stuff@trout.me.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

