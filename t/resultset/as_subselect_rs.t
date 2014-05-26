use strict;
use warnings;

use Test::More;
use Test::Exception;

use lib qw(t/lib);
use DBICTest ':DiffSQL';

my $schema = DBICTest->init_schema();

my $new_rs = $schema->resultset('Artist')->search({
   'artwork_to_artist.artist_id' => 1
}, {
   join => 'artwork_to_artist'
});
lives_ok { $new_rs->count } 'regular search works';
lives_ok { $new_rs->search({ 'artwork_to_artist.artwork_cd_id' => 1})->count }
   '... and chaining off that using join works';
lives_ok { $new_rs->search({ 'artwork_to_artist.artwork_cd_id' => 1})->as_subselect_rs->count }
   '... and chaining off the virtual view works';
dies_ok  { $new_rs->as_subselect_rs->search({'artwork_to_artist.artwork_cd_id'=> 1})->count }
   q{... but chaining off of a virtual view using join doesn't work};

my $book_rs = $schema->resultset ('BooksInLibrary')->search ({}, { join => 'owner' });

is_same_sql_bind (
  $book_rs->as_subselect_rs->as_query,
  '(SELECT me.id, me.source, me.owner, me.title, me.price
      FROM (
        SELECT me.id, me.source, me.owner, me.title, me.price
          FROM books me
          JOIN owners owner ON owner.id = me.owner
        WHERE ( source = ? )
      ) me
  )',
  [ [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' }
      => 'Library' ] ],
  'Resultset-class attributes do not seep outside of the subselect',
);

is_same_sql_bind(
  $schema->resultset('CD')->search ({}, {
    rows => 2,
    join => [ 'genre', { artist => 'cds' } ],
    distinct => 1,
    columns => {
      title => 'me.title',
      artist__name => 'artist.name',
      genre__name => 'genre.name',
      cds_for_artist => \ '(SELECT COUNT(*) FROM cds WHERE cd.artist = artist.id)',
    },
    order_by => { -desc => 'me.year' },
  })->count_rs->as_query,
  '(
    SELECT COUNT( * )
      FROM (
        SELECT artist.name AS artist__name, (SELECT COUNT(*) FROM cds WHERE cd.artist = artist.id), genre.name AS genre__name, me.title, me.year
          FROM cd me
          LEFT JOIN genre genre
            ON genre.genreid = me.genreid
          JOIN artist artist ON artist.artistid = me.artist
        GROUP BY artist.name, (SELECT COUNT(*) FROM cds WHERE cd.artist = artist.id), genre.name, me.title, me.year
        LIMIT ?
      ) me
  )',
  [ [{ sqlt_datatype => 'integer' } => 2 ] ],
);

done_testing;
