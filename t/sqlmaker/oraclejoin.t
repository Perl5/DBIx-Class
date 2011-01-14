use strict;
use warnings;

use Test::More;

BEGIN {
  require DBIx::Class::Optional::Dependencies;
  plan skip_all => 'Test needs ' . DBIx::Class::Optional::Dependencies->req_missing_for ('id_shortener')
    unless DBIx::Class::Optional::Dependencies->req_ok_for ('id_shortener');
}

use lib qw(t/lib);
use DBICTest;
use DBIx::Class::SQLMaker::OracleJoins;
use DBIC::SqlMakerTest;

my $sa = DBIx::Class::SQLMaker::OracleJoins->new;

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
  'SELECT cd.cdid, cd.artist, cd.title, cd.year, artist.artistid, artist.name FROM cd me, artist artist WHERE ( artist.artistid(+) = me.artist )', [],
  'WhereJoins search with empty where clause'
);

($sql, @bind) = $sa->select(
    [
        { me => "cd" },
        [
            { "-join_type" => "", artist => "artist" },
            { "artist.artistid" => "me.artist" },
        ],
    ],
    [ 'cd.cdid', 'cd.artist', 'cd.title', 'cd.year', 'artist.artistid', 'artist.name' ],
    { 'artist.artistid' => 3 },
    undef
);
is_same_sql_bind(
  $sql, \@bind,
  'SELECT cd.cdid, cd.artist, cd.title, cd.year, artist.artistid, artist.name FROM cd me, artist artist WHERE ( ( ( artist.artistid = me.artist ) AND ( artist.artistid = ? ) ) )', [3],
  'WhereJoins search with where clause'
);

($sql, @bind) = $sa->select(
    [
        { me => "cd" },
        [
            { "-join_type" => "LEFT", artist => "artist" },
            { "artist.artistid" => "me.artist" },
        ],
    ],
    [ 'cd.cdid', 'cd.artist', 'cd.title', 'cd.year', 'artist.artistid', 'artist.name' ],
    [{ 'artist.artistid' => 3 }, { 'me.cdid' => 5 }],
    undef
);
is_same_sql_bind(
  $sql, \@bind,
  'SELECT cd.cdid, cd.artist, cd.title, cd.year, artist.artistid, artist.name FROM cd me, artist artist WHERE ( ( ( artist.artistid(+) = me.artist ) AND ( ( ( artist.artistid = ? ) OR ( me.cdid = ? ) ) ) ) )', [3, 5],
  'WhereJoins search with or in where clause'
);

done_testing;

