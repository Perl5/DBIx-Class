package DBIx::Class::SQLMaker::OracleJoins;

use warnings;
use strict;
use Module::Runtime ();

use base qw( DBIx::Class::SQLMaker::Oracle );

sub _build_base_renderer_class {
  Module::Runtime::use_module('DBIx::Class::SQLMaker::Renderer::OracleJoins');
}

1;

=pod

=head1 NAME

DBIx::Class::SQLMaker::OracleJoins - Pre-ANSI Joins-via-Where-Clause Syntax

=head1 PURPOSE

This module is used with Oracle < 9.0 due to lack of support for standard
ANSI join syntax.

=head1 SYNOPSIS

Not intended for use directly; used as the sql_maker_class for schemas and components.

=head1 DESCRIPTION

Implements pre-ANSI joins specified in the where clause.  Instead of:

    SELECT x FROM y JOIN z ON y.id = z.id

It will write:

    SELECT x FROM y, z WHERE y.id = z.id

It should properly support left joins, and right joins.  Full outer joins are
not possible due to the fact that Oracle requires the entire query be written
to union the results of a left and right join, and by the time this module is
called to create the where query and table definition part of the sql query,
it's already too late.

=head1 METHODS

=over

=item select

Overrides DBIx::Class::SQLMaker's select() method, which calls _oracle_joins()
to modify the column and table list before calling next::method().

=back

=head1 BUGS

Does not support full outer joins (however neither really does DBIC itself)

=head1 SEE ALSO

=over

=item L<DBIx::Class::Storage::DBI::Oracle::WhereJoins> - Storage class using this

=item L<DBIx::Class::SQLMaker> - Parent module

=item L<DBIx::Class> - Duh

=back

=head1 AUTHOR

Justin Wheeler C<< <jwheeler@datademons.com> >>

=head1 CONTRIBUTORS

David Jack Olrik C<< <djo@cpan.org> >>

=head1 LICENSE

This module is licensed under the same terms as Perl itself.

=cut

