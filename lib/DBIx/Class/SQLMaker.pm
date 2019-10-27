package DBIx::Class::SQLMaker;

use strict;
use warnings;

use base qw(
  DBIx::Class::SQLMaker::ClassicExtensions
  SQL::Abstract::Classic
);

# NOTE THE LACK OF mro SPECIFICATION
# This is deliberate to ensure things will continue to work
# with ( usually ) untagged custom darkpan subclasses

1;

__END__

=head1 NAME

DBIx::Class::SQLMaker - An SQL::Abstract::Classic-like SQL maker class

=head1 DESCRIPTION

This module serves as a mere "nexus class" providing
L<SQL::Abstract::Classic>-like functionality to L<DBIx::Class> itself, and
to a number of database-engine-specific subclasses. This indirection is
explicitly maintained in order to allow swapping out the core of SQL
generation within DBIC on per-C<$schema> basis without major architectural
changes. It is guaranteed by design and tests that this fast-switching
will continue being maintained indefinitely.

=head2 Implementation switching

See L<DBIx::Class::Storage::DBI/connect_call_rebase_sqlmaker>

=head1 FURTHER QUESTIONS?

Check the list of L<additional DBIC resources|DBIx::Class/GETTING HELP/SUPPORT>.

=head1 COPYRIGHT AND LICENSE

This module is free software L<copyright|DBIx::Class/COPYRIGHT AND LICENSE>
by the L<DBIx::Class (DBIC) authors|DBIx::Class/AUTHORS>. You can
redistribute it and/or modify it under the same terms as the
L<DBIx::Class library|DBIx::Class/COPYRIGHT AND LICENSE>.
