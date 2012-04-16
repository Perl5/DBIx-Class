package DBIx::Class::Storage::DBI::Firebird;

use strict;
use warnings;

# Because DBD::Firebird is more or less a copy of
# DBD::Interbase, inherit all the workarounds contained
# in ::Storage::DBI::InterBase as opposed to inheriting
# directly from ::Storage::DBI::Firebird::Common
use base qw/DBIx::Class::Storage::DBI::InterBase/;

use mro 'c3';

=head1 NAME

DBIx::Class::Storage::DBI::Firebird - Driver for the Firebird RDBMS via
L<DBD::Firebird>

=head1 DESCRIPTION

This is an empty subclass of L<DBIx::Class::Storage::DBI::InterBase> for use
with L<DBD::Firebird>, see that driver for details.

=cut

1;

=head1 AUTHOR

See L<DBIx::Class/AUTHOR> and L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
# vim:sts=2 sw=2:
