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

=head1 AUTHORS

Matt S. Trout <perl-stuff@trout.me.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

