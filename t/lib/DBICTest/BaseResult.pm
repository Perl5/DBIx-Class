package #hide from pause
  DBICTest::BaseResult;

use strict;
use warnings;

#use base qw/DBIx::Class::Relationship::Cascade::Rekey DBIx::Class::Core/;
use base qw/DBIx::Class::Core/;
use DBICTest::BaseResultSet;

__PACKAGE__->table ('bogus');
__PACKAGE__->resultset_class ('DBICTest::BaseResultSet');

#sub add_relationship {
#  my $self = shift;
#  my $opts = $_[3] || {};
#  if (grep { $_ eq $_[0] } qw/
#    cds_90s cds_80s cds_84 artist_undirected_maps mapped_artists last_track
#  /) {
#    # nothing - join-dependent or non-cascadeable relationship
#  }
#  elsif ($opts->{is_foreign_key_constraint}) {
#    $opts->{on_update} ||= 'cascade';
#  }
#  else {
#    $opts->{cascade_rekey} = 1
#      unless ref $_[2] eq 'CODE';
#  }
#  $self->next::method(@_[0..2], $opts);
#}

1;
