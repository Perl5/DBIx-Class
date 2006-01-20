package DBIx::Class::PK::Auto::MSSQL;

use strict;
use warnings;

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto/);

sub last_insert_id {
  my( $id ) = $_[0]->result_source->storage->dbh->selectrow_array(
                                                    'SELECT @@IDENTITY' );
  return $id;
}

1;

=head1 NAME 

DBIx::Class::PK::Auto::MSSQL - Automatic Primary Key class for MSSQL

=head1 SYNOPSIS

    # In your table classes
    __PACKAGE__->load_components(qw/PK::Auto::MSSQL Core/);
    __PACKAGE__->set_primary_key('id');

=head1 DESCRIPTION

This class implements autoincrements for MSSQL.

=head1 AUTHORS

Brian Cassidy <bricas@cpan.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
