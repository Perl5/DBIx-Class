package # hide from PAUSE
    DBICTest::Schema::ArtistSourceName;

use warnings;
use strict;

use base 'DBICTest::Schema::Artist';
__PACKAGE__->table(__PACKAGE__->table);
__PACKAGE__->source_name('SourceNameArtists');

1;
