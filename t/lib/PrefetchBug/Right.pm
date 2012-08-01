package
    PrefetchBug::Right;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table('prefetch_right');
__PACKAGE__->add_columns(qw/ id name category description propagates locked/);
__PACKAGE__->set_primary_key('id');

__PACKAGE__->has_many('prefetch_leftright', 'PrefetchBug::LeftRight', 'right_id');
1;
