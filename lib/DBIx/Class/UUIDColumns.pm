package DBIx::Class::UUIDColumns;
use base qw/Class::Data::Inheritable/;

use Data::UUID;

__PACKAGE__->mk_classdata( 'uuid_auto_columns' => [] );

=head1 NAME

DBIx::Class::UUIDColumns - Implicit uuid columns

=head1 SYNOPSIS

  pacakge Artist;
  __PACKAGE__->load_components(qw/UUIDColumns Core DB/);
  __PACKAGE__->uuid_columns( 'artist_id' );x

=head1 DESCRIPTION

This L<DBIx::Class> component resambles the behaviour of
L<Class::DBI::UUID>, to make some columns implicitly created as uuid.

Note that the component needs to be loaded before Core.

=head1 METHODS

=over 4

=item uuid_columns

=cut

# be compatible with Class::DBI::UUID
sub uuid_columns {
    my $self = shift;
    for (@_) {
	die "column $_ doesn't exist" unless $self->has_column($_);
    }
    $self->uuid_auto_columns(\@_);
}

sub insert {
    my ($self) = @_;
    for my $column (@{$self->uuid_auto_columns}) {
	$self->store_column( $column, $self->get_uuid )
	    unless defined $self->get_column( $column );
    }
    $self->next::method;
}

sub get_uuid {
    return Data::UUID->new->to_string(Data::UUID->new->create),
}

=back

=head1 AUTHORS

Chia-liang Kao <clkao@clkao.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
