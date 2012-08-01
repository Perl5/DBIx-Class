package PrefetchBug::Left;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table('prefetchbug_left');
__PACKAGE__->add_columns(
    id => { data_type => 'integer', is_auto_increment => 1 },
);

__PACKAGE__->set_primary_key('id');

__PACKAGE__->has_many(
    prefetch_leftright => 'PrefetchBug::LeftRight',
    'left_id'
);

1;
