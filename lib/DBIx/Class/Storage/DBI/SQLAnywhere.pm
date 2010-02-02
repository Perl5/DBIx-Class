package # hide from PAUSE
  DBIx::Class::Storage::DBI::SQLAnywhere;

use strict;
use warnings;
use base qw/DBIx::Class::Storage::DBI/;
use mro 'c3';

sub _rebless {
  my $self = shift;

  if (ref $self eq __PACKAGE__) {
    require DBIx::Class::Storage::DBI::Sybase::ASA;
    bless $self, 'DBIx::Class::Storage::DBI::Sybase::ASA';
    $self->_rebless;
  }
}

1;
