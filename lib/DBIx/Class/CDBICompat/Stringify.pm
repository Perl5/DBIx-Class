package DBIx::Class::CDBICompat::Stringify;

use strict;
use warnings;

use overload
  '""' => sub { shift->stringify_self };

sub stringify_self {
        my $self = shift;
        #return (ref $self || $self) unless $self;    # empty PK
        #return ref $self unless $self;
        my @cols = $self->columns('Stringify');
        #@cols = $self->primary_column unless @cols;
        #return join "/", map { $self->get($_) } @cols;
}

1;
