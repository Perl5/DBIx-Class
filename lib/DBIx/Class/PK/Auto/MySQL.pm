package DBIx::Class::PK::Auto::MySQL;

use strict;
use warnings;

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto/);

sub last_insert_id {
  return $_[0]->result_source->storage->dbh->{mysql_insertid};
}

1;

=head1 NAME 

DBIx::Class::PK::Auto::MySQL - Automatic Primary Key class for MySQL

=head1 SYNOPSIS

    # In your table classes
    __PACKAGE__->load_components(qw/PK::Auto::MySQL Core/);
    __PACKAGE__->set_primary_key('id');

=head1 DESCRIPTION

This class implements autoincrements for MySQL.

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

