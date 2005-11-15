package DBIx::Class::PK::Auto;

use base qw/Class::Data::Inheritable/;
use strict;
use warnings;

=head1 NAME 

DBIx::Class::PK::Auto - Automatic Primary Key class

=head1 SYNOPSIS

=head1 DESCRIPTION

This class overrides the insert method to get automatically
incremented primary keys.

You don't want to be using this directly - instead load the appropriate
one for your database, e.g. PK::Auto::SQLite

=head1 METHODS

=over 4

=item insert

Overrides insert so that it will get the value of autoincremented
primary keys.

=cut

sub insert {
  my ($self, @rest) = @_;
  my $ret = $self->NEXT::ACTUAL::insert(@rest);

  # if all primaries are already populated, skip auto-inc
  my $populated = 0;
  map { $populated++ if $self->$_ } $self->primary_columns;
  return $ret if ( $populated == scalar $self->primary_columns );

  my ($pri, $too_many) =
    (grep { $self->column_info($_)->{'auto_increment'} }
       $self->primary_columns)
    || $self->primary_columns;
  $self->throw( "More than one possible key found for auto-inc on ".ref $self )
    if $too_many;
  unless (defined $self->get_column($pri)) {
    $self->throw( "Can't auto-inc for $pri on ".ref $self.": no _last_insert_id method" )
      unless $self->can('last_insert_id');
    my $id = $self->last_insert_id;
    $self->throw( "Can't get last insert id" ) unless $id;
    $self->store_column($pri => $id);
  }
  return $ret;
}

=item sequence

Manually define the correct sequence for your table, to avoid the overhead
associated with looking up the sequence automatically.

=cut

__PACKAGE__->mk_classdata('sequence');

1;

=back

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

