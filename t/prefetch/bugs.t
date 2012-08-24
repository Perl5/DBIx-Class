use warnings;
use strict;

use Test::More;

use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema(
   no_populate => 1,
);

$schema->resultset('CD')->create({
   cdid => 0,
   artist => {
      artistid => 0,
      name => 0,
      rank => 0,
      charfield => 0,
   },
   title => 0,
   year => 0,
   genreid => 0,
   single_track => 0,
});

ok( $schema->resultset('CD')->search( {}, { prefetch => 'artist' })->first->artist, 'artist loads even if all columns are 0');

done_testing;
