package # hide from PAUSE
    DBICTest::Schema::ArtistSubclass;

use warnings;
use strict;

use base 'DBICTest::Schema::Artist';
use mro 'c3';

__PACKAGE__->table(__PACKAGE__->table);

1;