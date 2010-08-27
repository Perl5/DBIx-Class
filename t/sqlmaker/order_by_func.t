use strict;
use warnings;
use Test::More;

use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;

my $schema = DBICTest->init_schema();

my $rs = $schema->resultset('CD')->search({}, {
    'join' => 'tracks',
    order_by => {
        -desc => {
            count => 'tracks.track_id',
        },
    },
    distinct => 1,
    rows => 2,
    page => 1,
});
my $match = q{
    SELECT me.cdid, me.artist, me.title, me.year, me.genreid, me.single_track FROM cd me
    GROUP BY me.cdid, me.artist, me.title, me.year, me.genreid, me.single_track
    ORDER BY COUNT(tracks.trackid) DESC
};

TODO: {
    todo_skip 'order_by using function', 2;
    is_same_sql($rs->as_query, $match, 'order by with func query');

    ok($rs->count == 2, 'amount of rows return in order by func query');
}

done_testing;
