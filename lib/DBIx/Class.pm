package DBIx::Class;

use strict;
use warnings;

use base qw/DBIx::Class::CDBICompat DBIx::Class::Core/;

use vars qw($VERSION);

$VERSION = '0.01';

1;

=head1 NAME 

DBIx::Class - Because the brain is a terrible thing to waste.

=head1 SYNOPSIS

=head1 DESCRIPTION

This is a sql to oop mapper, inspired by the L<Class::DBI> framework, 
and meant to support compability with it, while restructuring the 
insides, and making it possible to support some new features like 
self-joins, distinct, group bys and more.

=head1 QUICKSTART

If you're using Class::DBI, replacing

use base qw/Class::DBI/;

with

use base qw/DBIx::Class::CDBICompat DBIx::Class::Core/;

will probably get you started.

If you're using AUTO_INCREMENT for your primary columns, you'll also want
PK::Auto and an appropriate PK::Auto::DBName (e.g. ::SQLite).

If you fancy playing around with DBIx::Class from scratch, then read the docs
for ::Table and ::Relationship,

use base qw/DBIx::Class/;

and have a look at t/lib/DBICTest.pm for a brief example.

=head1 AUTHORS

Matt S. Trout <perl-stuff@trout.me.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

