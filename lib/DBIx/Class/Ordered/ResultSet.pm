package DBIx::Class::Ordered::ResultSet;
use strict;
use base qw/DBIx::Class::ResultSet/;

sub update {
  warn "CALLING UPDATE FROM Ordered::ResultSet";
  shift->update_all(@_);
}

sub delete {
  warn "CALLING DELETE FROM Ordered::ResultSet";
  shift->delete_all(@_);
}

1;
