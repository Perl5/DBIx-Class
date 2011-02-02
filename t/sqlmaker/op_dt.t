use strict;
use warnings;

use Test::More;
use Test::Fatal;

use lib qw(t/lib);
use DBIC::SqlMakerTest;
use DateTime;

use_ok('DBICTest');

my $schema = DBICTest->init_schema();

my $sql_maker = $schema->storage->sql_maker;

my $date = DateTime->new(
   year => 2010,
   month => 12,
   day   => 14,
   hour  => 12,
   minute => 12,
   second => 12,
);

my $date2 = $date->clone->set_day(16);

use Devel::Dwarn;

Dwarn [$schema->resultset('Artist')->search(undef, {
   select => [
      [ -dt_diff => [second => { -dt => $date }, { -dt => $date2 }] ],
      [ -dt_diff => [day    => { -dt => $date }, { -dt => $date2 }] ],
   ],
   as => [qw(seconds days)],
   result_class => 'DBIx::Class::ResultClass::HashRefInflator',
   rows => 1,
})->all];

is_same_sql_bind (
  \[ $sql_maker->select ('artist', '*', { 'artist.when_began' => { -dt => $date } } ) ],
  "SELECT *
    FROM artist
    WHERE artist.when_began = ?
  ",
  [['artist.when_began', '2010-12-14 12:12:12']],
  '-dt works'
);

is_same_sql_bind (
  \[ $sql_maker->update ('artist',
    { 'artist.when_began' => { -dt => $date } },
    { 'artist.when_ended' => { '<' => { -dt => $date2 } } },
  ) ],
  "UPDATE artist
    SET artist.when_began = ?
    WHERE artist.when_ended < ?
  ",
  [
   ['artist.when_began', '2010-12-14 12:12:12'],
   ['artist.when_ended', '2010-12-16 12:12:12'],
  ],
  '-dt works'
);

is_same_sql_bind (
  \[ $sql_maker->select ('artist', '*', {
    -and => [
       { -op => [ '=', 12, { -dt_month => { -ident => 'artist.when_began' } } ] },
       { -op => [ '=', 2010, { -dt_get => [year => \'artist.when_began'] } ] },
       { -op => [ '=', 14, { -dt_get => [day_of_month => \'artist.when_began'] } ] },
       { -op => [ '=', 100, { -dt_diff => [second => { -ident => 'artist.when_began' }, \'artist.when_ended'] } ] },
       { -op => [ '=', 10, { -dt_diff => [day => { -ident => 'artist.when_played_last' }, \'artist.when_ended'] } ] },
    ]
  } ) ],
  "SELECT *
     FROM artist
     WHERE ( (
       ( ? = STRFTIME('%m', artist.when_began) ) AND
       ( ? = STRFTIME('%Y', artist.when_began) ) AND
       ( ? = STRFTIME('%d', artist.when_began) ) AND
       ( ? = ( STRFTIME('%s', artist.when_began) - STRFTIME('%s', artist.when_ended))) AND
       ( ? = ( JULIANDAY(artist.when_played_last) - JULIANDAY(artist.when_ended)))
     ) )
  ",
  [
   ['', 12],
   ['', 2010],
   ['', 14],
   ['', 100],
   ['', 10],
  ],
  '-dt_month, -dt_get, and -dt_diff work'
);

like exception { $sql_maker->select('foo', '*', { -dt_diff => [year => \'artist.lololol', \'artist.fail'] }) }, qr/date diff not supported for part "year" with database "SQLite"/, 'SQLite does not support year diff';

done_testing;
