package DBIx::Class::Storage::DBI::mysql;

use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI/;

# __PACKAGE__->load_components(qw/PK::Auto/);

sub _dbh_last_insert_id {
  my ($self, $dbh, $source, $col) = @_;
  $dbh->{mysql_insertid};
}

sub sqlt_type {
  return 'MySQL';
}

sub _svp_begin {
    my ($self, $dbh, $name) = @_;

    $dbh->do("SAVEPOINT $name");
}

sub _svp_release {
    my ($self, $dbh, $name) = @_;

    $dbh->do("RELEASE SAVEPOINT $name");
}

sub _svp_rollback {
    my ($self, $dbh, $name) = @_;

    $dbh->do("ROLLBACK TO SAVEPOINT $name")
}

1;

=head1 NAME

DBIx::Class::Storage::DBI::mysql - Automatic primary key class for MySQL

=head1 SYNOPSIS

  # In your table classes
  __PACKAGE__->load_components(qw/PK::Auto Core/);
  __PACKAGE__->set_primary_key('id');

=head1 DESCRIPTION

This class implements autoincrements for MySQL.

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
