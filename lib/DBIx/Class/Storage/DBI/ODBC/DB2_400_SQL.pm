package DBIx::Class::Storage::DBI::ODBC::DB2_400_SQL;
use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI::ODBC/;
use mro 'c3';

warn 'Major advances took place in the DBIC codebase since this driver'
  .' (::Storage::DBI::ODBC::DB2_400_SQL) was written. However since the'
  .' RDBMS in question is so rare it is not possible for us to test any'
  .' of the "new hottness". If you are using DB2 on AS-400 please get'
  .' in contact with the developer team:'
  .' http://search.cpan.org/dist/DBIx-Class/lib/DBIx/Class.pm#GETTING_HELP/SUPPORT'
  ."\n"
;

# FIXME
# Most likely all of this code is redundant and unnecessary. We should
# be able to simply use base qw/DBIx::Class::Storage::DBI::DB2/;
# Unfortunately nobody has an RDBMS engine to test with, so keeping
# things as-is for the time being

sub _dbh_last_insert_id {
    my ($self, $dbh, $source, $col) = @_;

    # get the schema/table separator:
    #    '.' when SQL naming is active
    #    '/' when system naming is active
    my $sep = $dbh->get_info(41);
    my $sth = $dbh->prepare_cached(
        "SELECT IDENTITY_VAL_LOCAL() FROM SYSIBM${sep}SYSDUMMY1", {}, 3);
    $sth->execute();

    my @res = $sth->fetchrow_array();

    return @res ? $res[0] : undef;
}

sub _sql_maker_opts {
    my ($self) = @_;

    $self->dbh_do(sub {
        my ($self, $dbh) = @_;

        return {
            limit_dialect => 'FetchFirst',
            name_sep => $dbh->get_info(41)
        };
    });
}

1;

=head1 NAME

DBIx::Class::Storage::DBI::ODBC::DB2_400_SQL - Support specific to DB2/400
over ODBC

=head1 SYNOPSIS

  # In your result (table) classes
  use base 'DBIx::Class::Core';
  __PACKAGE__->set_primary_key('id');


=head1 DESCRIPTION

This class implements support specific to DB2/400 over ODBC, including
auto-increment primary keys, SQL::Abstract::Limit dialect, and name separator
for connections using either SQL naming or System naming.


=head1 AUTHORS

Marc Mims C<< <marc@questright.com> >>

Based on DBIx::Class::Storage::DBI::DB2 by Jess Robinson.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
