package
    DBIx::Class::CDBICompat::Relationship;

use strict;
use warnings;

use DBIx::Class::_Util 'quote_sub';

=head1 NAME

DBIx::Class::CDBICompat::Relationship - Emulate the Class::DBI::Relationship object returned from meta_info()

=head1 DESCRIPTION

Emulate the Class::DBI::Relationship object returned from C<meta_info()>.

=cut

my %method2key = (
    name            => 'type',
    class           => 'self_class',
    accessor        => 'accessor',
    foreign_class   => 'class',
    args            => 'args',
);

quote_sub __PACKAGE__ . "::$_" => "\$_[0]->{$method2key{$_}}"
  for keys %method2key;

sub new {
    my($class, $args) = @_;

    return bless $args, $class;
}

1;
