package # hide from PAUSE
    MyStar;

use warnings;
use strict;

use base 'MyBase';

__PACKAGE__->set_table();
__PACKAGE__->columns(All => qw/starid name/);
__PACKAGE__->has_many(films => [ MyStarLink => 'film' ]);

# sub films { map $_->film, shift->_films }

sub create_sql {
  return qq{
    starid  TINYINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    name   VARCHAR(255)
  };
}

1;

