use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $cd    = $schema->resultset('CD')->first;
my $track_hash = {
    cd        => $cd,
    title     => 'Multicreate rocks',
    cd_single => {
        artist => $cd->artist,
        year   => 2008,
        title  => 'Disemboweling MultiCreate',
    },
};

my $track = $schema->resultset('Track')->new_result($track_hash);

isa_ok( $track, 'DBICTest::Track', 'Main Track object created' );
$track->insert;
ok( 1, 'created track' );

is( $track->title, 'Multicreate rocks', 'Correct Track title' );
is( $track->cd_single->title, 'Disemboweling MultiCreate' );

$track_hash->{trackid} = $track->trackid;
$track_hash->{cd_single}->{title} = 'Disemboweling MultiUpdate';
$schema->resultset('Track')->update_or_create($track_hash);
is( $track->cd_single->title, 'Disemboweling MultiUpdate', 'correct cd_single title' );

done_testing;
