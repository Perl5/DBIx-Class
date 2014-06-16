#!/usr/bin/env perl

use strict;
use warnings;

use MyApp::Schema;

use Path::Class 'file';
my $db_fn = file($INC{'MyApp/Schema.pm'})->dir->parent->file('db/example.db');

my $schema = MyApp::Schema->connect("dbi:SQLite:$db_fn");

my @artists = (['Michael Jackson'], ['Eminem']);
$schema->populate('Artist', [
    [qw/name/],
    @artists,
]);

my %albums = (
    'Thriller' => 'Michael Jackson',
    'Bad' => 'Michael Jackson',
    'The Marshall Mathers LP' => 'Eminem',
);

my @cds;
foreach my $lp (keys %albums) {
    my $artist = $schema->resultset('Artist')->find({
        name => $albums{$lp}
    });
    push @cds, [$lp, $artist->id];
}

$schema->populate('Cd', [
    [qw/title artist/],
    @cds,
]);


my %tracks = (
    'Beat It'         => 'Thriller',
    'Billie Jean'     => 'Thriller',
    'Dirty Diana'     => 'Bad',
    'Smooth Criminal' => 'Bad',
    'Leave Me Alone'  => 'Bad',
    'Stan'            => 'The Marshall Mathers LP',
    'The Way I Am'    => 'The Marshall Mathers LP',
);

my @tracks;
foreach my $track (keys %tracks) {
    my $cd = $schema->resultset('Cd')->find({
        title => $tracks{$track},
    });
    push @tracks, [$cd->id, $track];
}

$schema->populate('Track',[
    [qw/cd title/],
    @tracks,
]);
