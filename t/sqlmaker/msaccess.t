use strict;
use warnings;
use Test::More;
use lib qw(t/lib);
use DBICTest ':DiffSQL';

# the entire point of the subclass is that parenthesis have to be
# just right for ACCESS to be happy
# globalize for entirety of the test
$SQL::Abstract::Test::parenthesis_significant = 1;

my $schema = DBICTest->init_schema (storage_type => 'DBIx::Class::Storage::DBI::ACCESS', no_deploy => 1, quote_names => 1);

is_same_sql_bind(
  $schema->resultset('Artist')->search(
    {
      artistid => 1,
    },
    {
      join => [{ cds => 'tracks' }],
      '+select' => [ 'tracks.title' ],
      '+as'     => [ 'track_title'  ],
    }
  )->as_query,
  '(
    SELECT [me].[artistid], [me].[name], [me].[rank], [me].[charfield],
           [tracks].[title]
      FROM (
        (
          [artist] [me]
          LEFT JOIN cd [cds]
            ON [cds].[artist] = [me].[artistid]
        )
        LEFT JOIN [track] [tracks]
          ON [tracks].[cd] = [cds].[cdid]
      )
    WHERE ( [artistid] = ? )
  )',
  [
    [{ sqlt_datatype => 'integer', dbic_colname => 'artistid' }
      => 1 ],
  ],
  'correct SQL for two-step left join'
);

is_same_sql_bind(
  $schema->resultset('Track')->search(
    {
      trackid => 1,
    },
    {
      join => [{ cd => 'artist' }],
      '+select' => [ 'artist.name' ],
      '+as'     => [ 'artist_name'  ],
    }
  )->as_query,
  '(
    SELECT [me].[trackid], [me].[cd], [me].[position], [me].[title], [me].[last_updated_on], [me].[last_updated_at],
           [artist].[name]
      FROM (
        (
          [track] [me]
          INNER JOIN cd [cd]
            ON [cd].[cdid] = [me].[cd]
        )
        INNER JOIN [artist] [artist]
          ON [artist].[artistid] = [cd].[artist]
      )
    WHERE ( [trackid] = ? )
  )',
  [
    [{ sqlt_datatype => 'integer', dbic_colname => 'trackid' }
      => 1 ],
  ],
  'correct SQL for two-step inner join',
);


my $sa = $schema->storage->sql_maker;
# the legacy tests assume no quoting - leave things as-is
local $sa->{quote_char};

#  my ($self, $table, $fields, $where, $order, @rest) = @_;
my ($sql, @bind) = $sa->select(
    [
        { me => "cd" },
        [
            { "-join_type" => "LEFT", artist => "artist" },
            { "artist.artistid" => { -ident => "me.artist" } },
        ],
    ],
    [ 'cd.cdid', 'cd.artist', 'cd.title', 'cd.year', 'artist.artistid', 'artist.name' ],
    undef,
    undef
);
is_same_sql_bind(
  $sql, \@bind,
  'SELECT cd.cdid, cd.artist, cd.title, cd.year, artist.artistid, artist.name FROM (cd me LEFT JOIN artist artist ON artist.artistid = me.artist)', [],
  'one-step join parenthesized'
);

($sql, @bind) = $sa->select(
    [
        { me => "cd" },
        [
            { "-join_type" => "LEFT", track => "track" },
            { "track.cd" => { -ident => "me.cdid" } },
        ],
        [
            { artist => "artist" },
            { "artist.artistid" => { -ident => "me.artist" } },
        ],
    ],
    [ 'track.title', 'cd.cdid', 'cd.artist', 'cd.title', 'cd.year', 'artist.artistid', 'artist.name' ],
    undef,
    undef
);
is_same_sql_bind(
  $sql, \@bind,
  'SELECT track.title, cd.cdid, cd.artist, cd.title, cd.year, artist.artistid, artist.name FROM ((cd me LEFT JOIN track track ON track.cd = me.cdid) INNER JOIN artist artist ON artist.artistid = me.artist)', [],
  'two-step join parenthesized and inner join prepended with INNER'
);

done_testing;
