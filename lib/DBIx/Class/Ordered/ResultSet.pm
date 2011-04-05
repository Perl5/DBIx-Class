package DBIx::Class::Ordered::ResultSet;
use strict;
use base qw/DBIx::Class::ResultSet/;

sub update {
  shift->update_all(@_);
}

sub delete {
  shift->delete_all(@_);
}

1;
