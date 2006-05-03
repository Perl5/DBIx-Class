package DBIx::Class::Storage::DBI::ODBC400;
use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI/;

sub last_insert_id
{
    my ($self) = @_;

    my $dbh = $self->_dbh;

    # get the schema/table separator:
    #    '.' when SQL naming is active
    #    '/' when sytem naming is active
    my $sep = $dbh->get_info(41);
    my $sth = $dbh->prepare_cached(
        "SELECT IDENTITY_VAL_LOCAL() FROM SYSIBM${sep}SYSDUMMY1", {}, 3);
    $sth->execute();

    my @res = $sth->fetchrow_array();

    return @res ? $res[0] : undef;
}

1;

=head1 NAME

DBIx::Class::Storage::DBI::ODBC400 - Automatic primary key class for DB2/400
over ODBC

=head1 SYNOPSIS

  # In your table classes
  __PACKAGE__->load_components(qw/PK::Auto Core/);
  __PACKAGE__->set_primary_key('id');

  # In your Schema class
  __PACKAGE__->storage_type('::DBI::ODBC400');

=for comment
$dbh->get_info(17) returns 'DB2/400 SQL' for an active DB2/400 connection over
ODBC.  This should facility automagically loading this module when
appropriate instead of manually specifying the storage_type as shown above.


=head1 DESCRIPTION

This class implements autoincrements for DB2/400 over ODBC.


=head1 AUTHORS

Marc Mims C<< <marc@questright.com> >>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
