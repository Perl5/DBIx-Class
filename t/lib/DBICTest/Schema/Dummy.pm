package # hide from PAUSE
    DBICTest::Schema::Dummy;

use strict;
use warnings;

use base qw/DBICTest::BaseResult/;

__PACKAGE__->table('dummy');
__PACKAGE__->add_columns(
    'id' => {
        data_type => 'integer',
        is_auto_increment => 1
    },
    'gittery' => {
        data_type => 'varchar',
        size      => 100,
        is_nullable => 1,
    },
);
__PACKAGE__->set_primary_key('id');

# part of a test, do not remove
__PACKAGE__->sequence('bogus');

1;
