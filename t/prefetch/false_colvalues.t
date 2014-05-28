use warnings;
use strict;

use Test::More;
use Test::Deep;

use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema( no_populate => 1 );

$schema->resultset('CD')->create({
  cdid => 0, title => '', year => 0, genreid => 0, single_track => 0, artist => {
    artistid => 0, name => '', rank => 0, charfield => 0,
  },
});

$schema->is_executed_querycount( sub {
  my $cd = $schema->resultset('CD')->search( {}, { prefetch => 'artist' })->next;

  cmp_deeply
    { $cd->get_columns },
    { artist => 0, cdid => 0, genreid => 0, single_track => 0, title => '', year => 0 },
    'Expected CD columns present',
  ;

  cmp_deeply
    { $cd->artist->get_columns },
    { artistid => 0, charfield => 0, name => "", rank => 0 },
    'Expected Artist columns present',
  ;
}, 1, 'Only one query fired - prefetch worked' );

done_testing;
