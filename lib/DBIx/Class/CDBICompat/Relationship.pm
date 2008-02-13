package
    DBIx::Class::CDBICompat::Relationship;

use strict;
use warnings;


=head1 NAME

DBIx::Class::CDBICompat::Relationship

=head1 DESCRIPTION

Emulate the Class::DBI::Relationship object returned from C<meta_info()>.

The C<args()> method does not return any useful result as it's not clear what it should contain nor if any of the information is applicable to DBIx::Class.

=cut

my %method2key = (
    name            => 'type',
    class           => 'self_class',
    accessor        => 'accessor',
    foreign_class   => 'class',
);

sub new {
    my($class, $args) = @_;
    
    return bless $args, $class;
}

for my $method (keys %method2key) {
    my $key = $method2key{$method};
    my $code = sub {
        $_[0]->{$key};
    };
    
    no strict 'refs';
    *{$method} = $code;
}

sub args {
    warn "args() is unlikely to ever work";
    return undef;
}


1;
