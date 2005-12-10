package DBIx::Class::Exception;

use strict;
use vars qw[@ISA $DBIC_EXCEPTION_CLASS];
use UNIVERSAL::require;

BEGIN {
    push( @ISA, $DBIC_EXCEPTION_CLASS || 'DBIx::Class::Exception::Base' );
}

package DBIx::Class::Exception::Base;

use strict;
use Carp ();

=head1 NAME

DBIx::Class::Exception - DBIC Exception Class

=head1 SYNOPSIS

   DBIx::Class::Exception->throw( qq/Fatal exception/ );

See also L<DBIx::Class>.

=head1 DESCRIPTION

This is a generic Exception class for DBIx::Class. You can easily
replace this with any mechanism implementing 'throw' by setting
$DBix::Class::Exception::DBIC_EXCEPTION_CLASS

=head1 METHODS

=head2 throw( $message )

=head2 throw( message => $message )

=head2 throw( error => $error )

Throws a fatal exception.

=cut

sub throw {
    my $class  = shift;
    my %params = @_ == 1 ? ( error => $_[0] ) : @_;

    my $message = $params{message} || $params{error} || $! || '';

    local $Carp::CarpLevel = (caller(1) eq 'NEXT' ? 2 : 1);

    Carp::croak($message);
}

=head1 AUTHOR

Marcus Ramberg <mramberg@cpan.org>

=head1 THANKS

Thanks to the L<Catalyst> framework, where this module was borrowed
from.

=head1 COPYRIGHT

This program is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
