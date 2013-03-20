package DBIx::Class::Storage::DBI::DBDFile;

use strict;
use base 'DBIx::Class::Storage::DBI';
use mro 'c3';
use DBIx::Class::Carp;
use namespace::clean;

__PACKAGE__->sql_maker_class('DBIx::Class::SQLMaker::SQLStatement');
__PACKAGE__->sql_quote_char('"');
__PACKAGE__->sql_limit_dialect('LimitXY');

# Unsupported options
sub _determine_supports_insert_returning { 0 };

# Statement caching currently buggy with either S:S or DBD::AnyData (and/or possibly others)
# Disable it here and look into fixing it later on
sub _init {
   my $self = shift;
   $self->next::method(@_);
   $self->disable_sth_caching(1);
}

# No support for transactions; warn and continue
sub txn_begin {
   carp_once <<'EOF' unless $ENV{DBIC_DBDFILE_TXN_NOWARN};
SQL::Statement-based drivers do not support transactions - proceeding at your own risk!

To turn off this warning, set the DBIC_DBDFILE_TXN_NOWARN environment variable.
EOF
}
sub txn_commit { 1; }
sub txn_rollback { shift->throw_exception('Transaction protection was ignored and unable to rollback - your data is likely inconsistent!'); }

# Nor is there any last_insert_id support (unless the driver supports it directly)
sub _dbh_last_insert_id { shift->throw_exception('SQL::Statement-based drivers do not support AUTOINCREMENT keys!  You will need to specify the PKs directly.'); }

1;

=head1 NAME

DBIx::Class::Storage::DBI::DBDFile - Base Class for SQL::Statement- / DBI::DBD::SqlEngine-based
DBD support in DBIx::Class

=head1 SYNOPSIS

This is the base class for DBDs that use L<SQL::Statement> and/or
L<DBI::DBD::SqlEngine|DBI::DBD::SqlEngine::Developers>, ie: based off of
L<DBD::File>.  This class is used for:

=over
=item L<DBD::AnyData>
=item L<DBD::TreeData>
=item L<DBD::CSV>
=item L<DBD::DBM>
=back

=head1 IMPLEMENTATION NOTES

=head2 Transactions

These drivers do not support transactions (and in fact, even the SQL syntax for
them).  Therefore, any attempts to use txn_* or svp_* methods will warn you once
and silently ignore the transaction protection.

=head2 SELECT ... FOR UPDATE/SHARE

This also is not supported, but it will silently ignore these.

=head1 AUTHOR

See L<DBIx::Class/AUTHOR> and L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut