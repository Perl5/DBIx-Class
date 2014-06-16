package # hide from PAUSE
    Film;

use warnings;
use strict;

use base 'DBIC::Test::SQLite';

__PACKAGE__->set_table('Movies');
__PACKAGE__->columns('Primary',   'Title');
__PACKAGE__->columns('Essential', qw( Title ));
__PACKAGE__->columns('Directors', qw( Director CoDirector ));
__PACKAGE__->columns('Other',     qw( Rating NumExplodingSheep HasVomit ));

sub create_sql {
  return qq{
    title                   VARCHAR(255),
    director                VARCHAR(80),
    codirector              VARCHAR(80),
    rating                  CHAR(5),
    numexplodingsheep       INTEGER,
    hasvomit                CHAR(1)
  }
}

sub create_test_film {
  return shift->create({
    Title             => 'Bad Taste',
    Director          => 'Peter Jackson',
    Rating            => 'R',
    NumExplodingSheep => 1,
  });
}

package DeletingFilm;

use base 'Film';
sub DESTROY { shift->delete }

1;

