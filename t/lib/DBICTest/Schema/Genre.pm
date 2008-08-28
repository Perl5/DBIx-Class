package DBICTest::Schema::Genre;

use strict;

use base 'DBIx::Class::Core';

__PACKAGE__->table('genre');
__PACKAGE__->add_columns(qw/genreid name/);
__PACKAGE__->set_primary_key('genreid');

1;
package DBICTest::Schema::Genre;

use strict;

use base 'DBIx::Class::Core';

__PACKAGE__->table('genre');
__PACKAGE__->add_columns(qw/genreid name/);
__PACKAGE__->set_primary_key('genreid');

1;
