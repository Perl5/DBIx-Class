package DBIx::Class::Storage::DBI::Oracle;

use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI/;

sub _rebless {
    my ($self) = @_;

    my $version = eval { $self->_dbh->get_info(18); };

    if ( !$@ ) {
        my ($major, $minor, $patchlevel) = split(/\./, $version);

        # Default driver
        my $class = $major >= 8
          ? 'DBIx::Class::Storage::DBI::Oracle::WhereJoins'
          : 'DBIx::Class::Storage::DBI::Oracle::Generic';

        # Load and rebless
        eval "require $class";

        bless $self, $class unless $@;
    }
}


1;

=head1 NAME

DBIx::Class::Storage::DBI::Oracle - Base class for Oracle driver

=head1 SYNOPSIS

  # In your table classes
  __PACKAGE__->load_components(qw/Core/);

=head1 DESCRIPTION

This class simply provides a mechanism for discovering and loading a sub-class
for a specific version Oracle backend.  It should be transparent to the user.


=head1 AUTHORS

David Jack Olrik C<< <djo@cpan.org> >>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
