package
    PrefetchBug::LeftRight;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table('left_right');
__PACKAGE__->add_columns(
    left_id => { data_type => 'integer' },
    right_id => { data_type => 'integer' },
    value => {});

__PACKAGE__->set_primary_key('left_id', 'right_id');
__PACKAGE__->belongs_to(left => 'PrefetchBug::Left', 'left_id');
__PACKAGE__->belongs_to(
    right => 'PrefetchBug::Right',
    'right_id',
#    {join_type => 'left'}
);


1;
