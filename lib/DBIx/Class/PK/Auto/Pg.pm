package DBIx::Class::PK::Auto::Pg;

use strict;
use warnings;

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto/);

sub last_insert_id {
  my $self = shift;
  $self->get_autoinc_seq unless $self->{_autoinc_seq};
  $self->storage->dbh->last_insert_id(undef,undef,undef,undef,
    {sequence=>$self->{_autoinc_seq}});
}

sub get_autoinc_seq {
  my $self = shift;
  
  # return the user-defined sequence if known
  if ($self->sequence) {
    return $self->{_autoinc_seq} = $self->sequence;
  }
  
  my @pri = keys %{ $self->_primaries };
  my $dbh = $self->storage->dbh;
  while (my $col = shift @pri) {
    my $info = $dbh->column_info(undef,undef,$self->table,$col)->fetchrow_arrayref;
    if (defined $info->[12] and $info->[12] =~ 
      /^nextval\('"?([^"']+)"?'::(?:text|regclass)\)/)
    {
      $self->{_autoinc_seq} = $1;
      last;
    } 
  }
}

1;

=head1 NAME 

DBIx::Class::PK::Auto::Pg - Automatic Primary Key class for Postgresql

=head1 SYNOPSIS

=head1 DESCRIPTION

This class implements autoincrements for Postgresql.

=head1 AUTHORS

Marcus Ramberg <m.ramberg@cpan.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

