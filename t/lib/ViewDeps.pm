package # hide from PAUSE
    ViewDeps;

use strict;
use warnings;
use parent qw(DBIx::Class::Schema);
use aliased 'DBIx::Class::ResultSource::View' => 'View';

__PACKAGE__->load_namespaces;

#for my $p (__PACKAGE__) {
  #$p->load_namespaces;
  #$_->attach_additional_sources
    #for grep $_->isa(View), map $p->source($_), $p->sources;
#}

1;
