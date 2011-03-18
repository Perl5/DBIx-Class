use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;
use Test::Exception;

my $schema = DBICTest->init_schema;

dies_ok {
   my $rsq = $schema->resultset('Artist')->search({
      'artwork_to_artist.artwork_cd_id' => 5,
   }, {
      join => { artwork_to_artist => { -unknown_arg => 'foo' } }
   })->as_query
} 'dies on unknown rel args';

lives_ok {
   my $rsq = $schema->resultset('Artist')->search({
      'a2a.artwork_cd_id' => 5,
   }, {
      join => { artwork_to_artist => { -alias => 'a2a' } }
   })->as_query
} 'lives for arg -alias';

lives_ok {
   my $rsq = $schema->resultset('Artist')->search({
      'artwork_to_artist.artwork_cd_id' => 5,
   }, {
      join => { artwork_to_artist => { -join_type => 'left' } }
   })->as_query
} 'lives for arg -join_type';

is_same_sql_bind( $schema->resultset('Artist')->search({
   'a2a.artwork_cd_id' => 5,
}, {
   join => {
      'artwork_to_artist' => { -alias => 'a2a', -join_type => 'right' }
   }
})->as_query,
'(
   SELECT me.artistid, me.name, me.rank, me.charfield
   FROM artist me
   RIGHT JOIN artwork_to_artist a2a
     ON a2a.artist_id = me.artistid
   WHERE ( a2a.artwork_cd_id = ? )
)', [[ 'a2a.artwork_cd_id' => 5 ]], 'rel is aliased and join-typed correctly'
);

done_testing;
