package DBIx::Class::PK::Auto;

use strict;
use warnings;

=head1 NAME 

DBIx::Class::PK::Auto - Automatic Primary Key class

=head1 SYNOPSIS

=head1 DESCRIPTION

This class overrides the insert method to get automatically
incremented primary keys.

=head1 METHODS

=over 4

=item insert

Overrides insert so that it will get the value of autoincremented
primary keys.

=cut

sub insert {
  my ($self, @rest) = @_;
  my $ret = $self->NEXT::ACTUAL::insert(@rest);
  my ($pri, $too_many) =
    (grep { $self->_primaries->{$_}{'auto_increment'} }
       keys %{ $self->_primaries })
    || (keys %{ $self->_primaries });
  $self->throw( "More than one possible key found for auto-inc on ".ref $self )
    if $too_many;
  unless (defined $self->get_column($pri)) {
    $self->throw( "Can't auto-inc for $pri on ".ref $self.": no _last_insert_id method" )
      unless $self->can('_last_insert_id');
    my $id = $self->_last_insert_id;
    $self->throw( "Can't get last insert id" ) unless $id;
    $self->store_column($pri => $id);
  }
  return $ret;
}

1;

=back

=head1 AUTHORS

Matt S. Trout <perl-stuff@trout.me.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

