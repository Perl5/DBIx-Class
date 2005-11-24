package DBIx::Class::PK::Auto::Pg;

use strict;
use warnings;

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto/);

sub last_insert_id {
  my $self=shift;
  $self->get_autoinc_seq unless $self->{_autoinc_seq};
  $self->storage->dbh->last_insert_id(undef,undef,undef,undef,
    {sequence=>$self->{_autoinc_seq}});
}

sub get_autoinc_seq {
  my $self=shift;
  
  # return the user-defined sequence if known
  if ($self->sequence) {
    return $self->{_autoinc_seq} = $self->sequence;
  }
  
  my $dbh= $self->storage->dbh;
    my $sth	= $dbh->column_info( undef, undef, $self->_table_name, '%');
    while (my $foo = $sth->fetchrow_arrayref){
      if(defined $foo->[12] && $foo->[12] =~ /^nextval/) {
        ($self->{_autoinc_seq}) = $foo->[12] =~ 
          m!^nextval\('"?([^"']+)"?'::(?:text|regclass)\)!;
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

