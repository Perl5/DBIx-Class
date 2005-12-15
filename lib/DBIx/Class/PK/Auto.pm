package DBIx::Class::PK::Auto;

#use base qw/DBIx::Class::PK/;
use base qw/DBIx::Class/;
use strict;
use warnings;

=head1 NAME 

DBIx::Class::PK::Auto - Automatic Primary Key class

=head1 SYNOPSIS

    # In your table classes (replace PK::Auto::SQLite with your
    # database)
    __PACKAGE__->load_components(qw/PK::Auto::SQLite Core/);
    __PACKAGE__->set_primary_key('id');

=head1 DESCRIPTION

This class overrides the insert method to get automatically
incremented primary keys.

You don't want to be using this directly - instead load the
appropriate one for your database, e.g. C<PK::Auto::SQLite>, before
C<Core>.

=head1 LOGIC

PK::Auto does this by letting the database assign the primary key
field and fetching the assigned value afterwards.

=head1 METHODS

=head2 insert

Overrides insert so that it will get the value of autoincremented
primary keys.

=cut

sub insert {
  my ($self, @rest) = @_;
  my $ret = $self->next::method(@rest);

  # if all primaries are already populated, skip auto-inc
  my $populated = 0;
  map { $populated++ if defined $self->get_column($_) } $self->primary_columns;
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

=head2 sequence

Manually define the correct sequence for your table, to avoid the overhead
associated with looking up the sequence automatically.

=cut

__PACKAGE__->mk_classdata('sequence');

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

