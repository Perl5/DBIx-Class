use strict;
use warnings;
use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;

use DBIx::Class::SQLMaker::ACCESS ();

my $sa = DBIx::Class::SQLMaker::ACCESS->new;

#  my ($self, $table, $fields, $where, $order, @rest) = @_;
my ($sql, @bind) = $sa->select(
    [
        { me => "cd" },
        [
            { "-join_type" => "LEFT", artist => "artist" },
            { "artist.artistid" => "me.artist" },
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
            { "track.cd" => "me.cdid" },
        ],
        [
            { artist => "artist" },
            { "artist.artistid" => "me.artist" },
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
