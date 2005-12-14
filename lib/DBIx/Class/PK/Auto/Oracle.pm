package DBIx::Class::PK::Auto::Oracle;

use strict;
use warnings;

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto/);

sub last_insert_id {
  my $self = shift;
  $self->get_autoinc_seq unless $self->{_autoinc_seq};
  my $sql = "SELECT " . $self->{_autoinc_seq} . ".currval FROM DUAL";
  my ($id) = $self->storage->dbh->selectrow_array($sql);
  return $id;  
}

sub get_autoinc_seq {
  my $self = shift;
  
  # return the user-defined sequence if known
  if ($self->sequence) {
    return $self->{_autoinc_seq} = $self->sequence;
  }
  
  # look up the correct sequence automatically
  my $dbh = $self->storage->dbh;
  my $sql = qq{
    SELECT trigger_body FROM ALL_TRIGGERS t
    WHERE t.table_name = ?
    AND t.triggering_event = 'INSERT'
    AND t.status = 'ENABLED'
  };
  # trigger_body is a LONG
  $dbh->{LongReadLen} = 64 * 1024 if ($dbh->{LongReadLen} < 64 * 1024);
  my $sth = $dbh->prepare($sql);
  $sth->execute( uc($self->_table_name) );
  while (my ($insert_trigger) = $sth->fetchrow_array) {
    if ($insert_trigger =~ m!(\w+)\.nextval!i ) {
      $self->{_autoinc_seq} = uc($1);
    }
  }
  unless ($self->{_autoinc_seq}) {
    die "Unable to find a sequence INSERT trigger on table '" . $self->_table_name . "'.";
  }
}

1;

=head1 NAME 

DBIx::Class::PK::Auto::Oracle - Automatic Primary Key class for Oracle

=head1 SYNOPSIS

=head1 DESCRIPTION

This class implements autoincrements for Oracle.

=head1 AUTHORS

Andy Grundman <andy@hybridized.org>

Scott Connelly <scottsweep@yahoo.com>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

