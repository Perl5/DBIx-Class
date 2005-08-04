package DBIx::Class;

use strict;
use warnings;

use vars qw($VERSION);
use base;

$VERSION = '0.01';

sub load_components {
  my $class = shift;
  my @comp = map { "DBIx::Class::$_" } grep { $_ !~ /^#/ } @_;
  foreach my $comp (@comp) {
    eval "use $comp";
    die $@ if $@;
  }
  no strict 'refs';
  unshift(@{"${class}::ISA"}, @comp);
}

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

use base qw/DBIx::Class/;
__PACKAGE__->load_components(qw/CDBICompat Core DB/);

will probably get you started.

If you're using AUTO_INCREMENT for your primary columns, you'll also want
yo load the approriate PK::Auto subclass - e.g.

__PACKAGE__->load_components(qw/CDBICompat PK::Auto::SQLite Core DB/);

(with is what ::Test::SQLite does to present the Class::DBI::Test::SQLite
interface)

If you fancy playing around with DBIx::Class from scratch, then read the docs
for ::Table and ::Relationship,

use base qw/DBIx::Class/;
__PACKAGE__->load_components(qw/Core DB/);

and have a look at t/lib/DBICTest.pm for a brief example.

=head1 AUTHORS

Matt S. Trout <perl-stuff@trout.me.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

