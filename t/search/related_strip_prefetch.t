use strict;
use warnings;

use Test::More;
use Test::Exception;

use lib qw(t/lib);
use DBIC::SqlMakerTest;
use DBICTest;

my $schema = DBICTest->init_schema();

my $rs = $schema->resultset('CD')->search (
  { 'tracks.id' => { '!=', 666 }},
  { join => 'artist', prefetch => 'tracks' }
);

my $rel_rs = $rs->search_related ('tags');

is_same_sql_bind (
  $rel_rs->as_query,
  '(
    SELECT tags.tagid, tags.cd, tags.tag 
      FROM cd me
      JOIN artist artist ON artist.artistid = me.artist
      LEFT JOIN track tracks ON tracks.cd = me.cdid
      LEFT JOIN tags tags ON tags.cd = me.cdid
    WHERE ( tracks.id != ? )
  )',
  [ [ 'tracks.id' => 666 ] ],
  'Prefetch spec successfully stripped on search_related'
);

done_testing;
