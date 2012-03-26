package DBICTest::Schema::EventPrePostInflate;

use strict;
use warnings;
use base qw/DBICTest::BaseResult/;

__PACKAGE__->load_components(qw/InflateColumn::DateTime/);

__PACKAGE__->table('event_pre_post_inflate');

__PACKAGE__->add_columns(
  id => { data_type => 'integer', is_auto_increment => 1 },
  starts_at => { data_type => 'datetime', is_nullable => 1 },
);

__PACKAGE__->set_primary_key('id');

## expecting carp
sub _post_inflate_datetime {
    my ($self, @args) = @_;
    return $self->next::method(@args);
}

## expecting carp
sub _pre_deflate_datetime {
    my ($self, @args) = @_;
    return $self->next::method(@args);
}

1;
