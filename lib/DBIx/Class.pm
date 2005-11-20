package DBIx::Class;

use strict;
use warnings;

use vars qw($VERSION);
use base qw/DBIx::Class::Componentised Class::Data::Inheritable/;

$VERSION = '0.03999_01';


1;

=head1 NAME 

DBIx::Class - Extensible and flexible object <-> relational mapper.

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

If you're using Class::DBI, and want an easy and fast way of migrating to
DBIx::Class look at L<DBIx::Class::CDBICompat>.

There are two ways of using DBIx::Class, the 'simple' and the 'schema' one.

The 'simple' way of using DBIx::Class needs less classes than the 'schema'
way but doesn't give you the ability to use different database connections.

Some examples where different database connections are useful are:

different users with different rights
different databases with the same schema.

=head1 Simple

First you need to create a base class all other classes inherit from.

Look at L<DBIx::Class::DB> how to do this

Next you need to create a class for every table you want to use with
DBIx::Class.

Look at L<DBIx::Class::Table> how to do this.


=head2 Schema

With this approach the table classes inherit directly from DBIx::Class::Core,
although it might be a good idea to create a 'parent' class for all table
classes which inherits from DBIx::Class::Core and adds additional methods
needed by all table classes, e.g. reading a config file, loading auto primary
key support.

Look at L<DBIx::Class::Schema> how to do this.

If you need more hand-holding, check out the introduction in the 
manual below.

=head1 SEE ALSO

=over 4

=item L<DBIx::Class::Core> - DBIC Core Classes

=item L<DBIx::Class::CDBICompat> - L<Class::DBI> Compat layer.

=item L<DBIx::Class::Manual> - User's manual.

=back

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

