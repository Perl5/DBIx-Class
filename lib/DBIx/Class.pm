package DBIx::Class;

use strict;
use warnings;

use vars qw($VERSION);
use base qw/DBIx::Class::Componentised Class::Data::Accessor/;

sub mk_classdata { shift->mk_classaccessor(@_); }

1;

=head1 NAME 

DBIx::Class - Extensible and flexible object <-> relational mapper.

=head1 SYNOPSIS

=head1 DESCRIPTION

This is an SQL to OO mapper, inspired by the L<Class::DBI> framework, 
and meant to support compability with it, while restructuring the 
internals and making it possible to support some new features like 
self-joins, distinct, group bys and more.

This project is still at an early stage, so the maintainers don't make
any absolute promise that full backwards-compatibility will be supported;
however, if we can without compromising the improvements we're trying to
make, we will, and any non-compatible changes will merit a full justification
on the mailing list and a CPAN developer release for people to test against.

The community can be found via -

  Mailing list: http://lists.rawmode.org/mailman/listinfo/dbix-class/

  SVN: http://dev.catalyst.perl.org/repos/bast/trunk/DBIx-Class/

  Wiki: http://dbix-class.shadowcatsystems.co.uk/

  IRC: irc.perl.org#dbix-class

=head1 QUICKSTART

If you're using L<Class::DBI>, and want an easy and fast way of migrating to
DBIx::Class, take a look at L<DBIx::Class::CDBICompat>.

There are two ways of using DBIx::Class, the "simple" way and the "schema" way.
The "simple" way of using DBIx::Class needs less classes than the "schema"
way but doesn't give you the ability to easily use different database connections.

Some examples where different database connections are useful are:

different users with different rights
different databases with the same schema.

=head2 Simple

First you need to create a base class which all other classes will inherit from.
See L<DBIx::Class::DB> for information on how to do this.

Then you need to create a class for every table you want to use with DBIx::Class.
See L<DBIx::Class::Table> for information on how to do this.

=head2 Schema

With this approach, the table classes inherit directly from DBIx::Class::Core,
although it might be a good idea to create a "parent" class for all table
classes that inherits from DBIx::Class::Core and adds additional methods
needed by all table classes, e.g. reading a config file or loading auto primary
key support.

Look at L<DBIx::Class::Schema> for information on how to do this.

If you need more help, check out the introduction in the 
manual below.

=head1 SEE ALSO

=head2 L<DBIx::Class::Core> - DBIC Core Classes

=head2 L<DBIx::Class::Manual> - User's manual

=head2 L<DBIx::Class::CDBICompat> - L<Class::DBI> Compat layer

=head2 L<DBIx::Class::DB> - database-level methods

=head2 L<DBIx::Class::Table> - table-level methods

=head2 L<DBIx::Class::Row> - row-level methods

=head2 L<DBIx::Class::PK> - primary key methods

=head2 L<DBIx::Class::ResultSet> - search result-set methods

=head2 L<DBIx::Class::Relationship> - relationships between tables

=head1 AUTHOR

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 CONTRIBUTORS

Andy Grundman <andy@hybridized.org>

Brian Cassidy <bricas@cpan.org>

Dan Kubb <dan.kubb-cpan@onautopilot.com>

Dan Sully <daniel@cpan.org>

David Kamholz <dkamholz@cpan.org>

Jules Bean

Marcus Ramberg <mramberg@cpan.org>

Paul Makepeace

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

