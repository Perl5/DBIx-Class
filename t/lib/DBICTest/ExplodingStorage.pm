package DBICTest::ExplodingStorage::Sth;

sub execute {
  die "Kablammo!";
}

sub bind_param {}

package DBICTest::ExplodingStorage;

use strict;
use warnings;

use base 'DBIx::Class::Storage::DBI::SQLite';

my $count = 0;
sub sth {
  my ($self, $sql) = @_;
  return bless {},  "DBICTest::ExplodingStorage::Sth" unless $count++;
  return $self->next::method($sql);
}

sub connected {
  return 0 if $count == 1;
  return shift->next::method(@_);
}

1;
