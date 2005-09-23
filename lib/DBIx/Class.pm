package DBIx::Class;

use strict;
use warnings;

use vars qw($VERSION);
use base qw/DBIx::Class::Componentised/;

$VERSION = '0.03001';


1;

=head1 NAME 

DBIx::Class - Because the brain is a terrible thing to waste.

=head1 SYNOPSIS

=head1 DESCRIPTION

This is a sql to oop mapper, inspired by the L<Class::DBI> framework, 
and meant to support compability with it, while restructuring the 
insides, and making it possible to support some new features like 
self-joins, distinct, group bys and more.

It's currently considered EXPERIMENTAL - bring this near a production
database at your own risk! The API is *not* fixed yet, although most of
the primitives should be good for the future and any API changes will be
posted to the mailing list before they're committed.

The community can be found via -

  Mailing list: http://lists.rawmode.org/mailman/listinfo/dbix-class/

  SVN: http://dev.catalyst.perl.org/repos/bast/trunk/DBIx-Class/

  Wiki: http://dbix-class.shadowcatsystems.co.uk/

  IRC: irc.perl.org#dbix-class

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
for DBIx::Class::Table, ::Row, ::Schema, ::DB and ::Relationship,

  use base qw/DBIx::Class/;
  __PACKAGE__->load_components(qw/Core DB/);

and have a look at t/lib/DBICTest.pm for a brief example.

=head1 AUTHOR

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 CONTRIBUTORS

Andy Grundman <andy@hybridized.org>

Brian Cassidy <bricas@cpan.org>

Dan Kubb <dan.kubb-cpan@onautopilot.com>

Dan Sully <daniel@cpan.org>

davekam

Marcus Ramberg <mramberg@cpan.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

