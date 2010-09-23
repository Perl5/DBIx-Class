package # hide from PAUSE
    DBICTest::Schema::Bookmark;

use base qw/DBICTest::BaseResult/;

use strict;
use warnings;

__PACKAGE__->table('bookmark');
__PACKAGE__->add_columns(
    'id' => {
        data_type => 'integer',
        is_auto_increment => 1
    },
    'link' => {
        data_type => 'integer',
        is_nullable => 1,
    },
);

__PACKAGE__->set_primary_key('id');

require DBICTest::Schema::Link; # so we can get a columnlist
__PACKAGE__->belongs_to(
    link => 'DBICTest::Schema::Link', 'link', {
    on_delete => 'SET NULL',
    join_type => 'LEFT',
    proxy => { map { join('_', 'link', $_) => $_ } DBICTest::Schema::Link->columns },
});

1;
