package DBIx::Class::Storage::DBI::Pg;

use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI/;

# __PACKAGE__->load_components(qw/PK::Auto/);

sub last_insert_id {
  my ($self, $source) = @_;
  $self->get_autoinc_seq unless $self->{_autoinc_seq};
  $self->_dbh->last_insert_id(undef,undef,undef,undef,
    {sequence=>$self->{_autoinc_seq}});
}

sub get_autoinc_seq {
  my $self = shift;
  
  # return the user-defined sequence if known
  if ($source->sequence) {
    return $self->{_autoinc_seq} = $source->sequence;
  }
  
  my @pri = $source->primary_columns;
  my $dbh = $self->_dbh;
  my ($schema,$table) = $source->name =~ /^(.+)\.(.+)$/ ? ($1,$2) : (undef,$sou
rce->table);
  while (my $col = shift @pri) {
    my $info = $dbh->column_info(undef,$schema,$table,$col)->fetchrow_arrayref;
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

DBIx::Class::Storage::DBI::Pg - Automatic primary key class for PostgreSQL

=head1 SYNOPSIS

  # In your table classes
  __PACKAGE__->load_components(qw/PK::Auto Core/);
  __PACKAGE__->set_primary_key('id');
  __PACKAGE__->sequence('mysequence');

=head1 DESCRIPTION

This class implements autoincrements for PostgreSQL.

=head1 AUTHORS

Marcus Ramberg <m.ramberg@cpan.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
