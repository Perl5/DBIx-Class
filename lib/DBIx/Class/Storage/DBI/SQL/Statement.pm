package DBIx::Class::Storage::DBI::SQL::Statement;

use strict;
use base 'DBIx::Class::Storage::DBI';
use mro 'c3';
use namespace::clean;

__PACKAGE__->sql_maker_class('DBIx::Class::SQLMaker::SQLStatement');
__PACKAGE__->sql_quote_char('"');
__PACKAGE__->sql_limit_dialect('LimitXY_NoBinds');

# Unsupported options
sub _determine_supports_insert_returning { 0 };

# Statement caching currently buggy with either S:S or DBD::AnyData (and/or possibly others)
# Disable it here and look into fixing it later on
sub _init {
   my $self = shift;
   $self->next::method(@_);
   $self->disable_sth_caching(1);
}

# No support for transactions; sorry...
sub txn_begin {
   my $self = shift;

   # Only certain internal calls are allowed through, and even then, we are merely
   # ignoring the txn part
   my $callers = join "\n", map { (caller($_))[3] } (1 .. 4);
   return $self->_get_dbh
      if ($callers =~ /
         DBIx::Class::Storage::DBI::insert_bulk|
         DBIx::Class::Relationship::CascadeActions::update
      /x);

   $self->throw_exception('SQL::Statement-based drivers do not support transactions!');
}
sub svp_begin { shift->throw_exception('SQL::Statement-based drivers do not support savepoints!'); }

# Nor is there any last_insert_id support (unless the driver supports it directly)
sub _dbh_last_insert_id { shift->throw_exception('SQL::Statement-based drivers do not support AUTOINCREMENT keys!  You will need to specify the PKs directly.'); }

# leftovers to support txn_begin exceptions
sub txn_commit { 1; }

1;

=head1 NAME

DBIx::Class::Storage::DBI::SQL::Statement - Base Class for SQL::Statement- / DBI::DBD::SqlEngine-based
DBD support in DBIx::Class

=head1 SYNOPSIS

This is the base class for DBDs that use L<SQL::Statement> and/or
L<DBI::DBD::SqlEngine|DBI::DBD::SqlEngine::Developers>.  This class is
used for:

=over
=item L<DBD::Sys>
=item L<DBD::AnyData>
=item L<DBD::TreeData>
=item L<DBD::SNMP>
=item L<DBD::PO>
=item L<DBD::CSV>
=item L<DBD::DBM>
=back

=head1 IMPLEMENTATION NOTES

=head2 Transactions

These drivers do not support transactions (and in fact, even the SQL syntax for
them).  Therefore, any attempts to use txn_* or svp_* methods will throw an
exception.

In a future release, they may be replaced with emulated functionality.  (Then
again, it would probably be added into L<SQL::Statement> instead.)

=head2 SELECT ... FOR UPDATE/SHARE

This also is not supported, but it will silently ignore these.

=head1 AUTHOR

See L<DBIx::Class/AUTHOR> and L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut