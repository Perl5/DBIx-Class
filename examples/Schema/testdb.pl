#!/usr/bin/env perl

use warnings;
use strict;

use lib '.';
use MyApp::Schema;

use Path::Class 'file';
my $db_fn = file($INC{'MyApp/Schema.pm'})->dir->parent->file('db/example.db');

# for other DSNs, e.g. MySql, see the perldoc for the relevant dbd
# driver, e.g perldoc L<DBD::mysql>.
my $schema = MyApp::Schema->connect("dbi:SQLite:$db_fn");

get_tracks_by_cd('Bad');
get_tracks_by_artist('Michael Jackson');

get_cd_by_track('Stan');
get_cds_by_artist('Michael Jackson');

get_artist_by_track('Dirty Diana');
get_artist_by_cd('The Marshall Mathers LP');


sub get_tracks_by_cd {
    my $cdtitle = shift;
    print "get_tracks_by_cd($cdtitle):\n";
    my $rs = $schema->resultset('Track')->search(
        {
            'cd.title' => $cdtitle
        },
        {
            join     => [qw/ cd /],
        }
    );
    while (my $track = $rs->next) {
        print $track->title . "\n";
    }
    print "\n";
}

sub get_tracks_by_artist {
    my $artistname = shift;
    print "get_tracks_by_artist($artistname):\n";
    my $rs = $schema->resultset('Track')->search(
        {
            'artist.name' => $artistname
        },
        {
            join => {
                'cd' => 'artist'
            },
        }
    );
    while (my $track = $rs->next) {
        print $track->title . " (from the CD '" . $track->cd->title
          . "')\n";
    }
    print "\n";
}

sub get_cd_by_track {
    my $tracktitle = shift;
    print "get_cd_by_track($tracktitle):\n";
    my $rs = $schema->resultset('Cd')->search(
        {
            'tracks.title' => $tracktitle
        },
        {
            join     => [qw/ tracks /],
        }
    );
    my $cd = $rs->first;
    print $cd->title . " has the track '$tracktitle'.\n\n";
}

sub get_cds_by_artist {
    my $artistname = shift;
    print "get_cds_by_artist($artistname):\n";
    my $rs = $schema->resultset('Cd')->search(
        {
            'artist.name' => $artistname
        },
        {
            join     => [qw/ artist /],
        }
    );
    while (my $cd = $rs->next) {
        print $cd->title . "\n";
    }
    print "\n";
}

sub get_artist_by_track {
    my $tracktitle = shift;
    print "get_artist_by_track($tracktitle):\n";
    my $rs = $schema->resultset('Artist')->search(
        {
            'tracks.title' => $tracktitle
        },
        {
            join => {
                'cds' => 'tracks'
            }
        }
    );
    my $artist = $rs->first;
    print $artist->name . " recorded the track '$tracktitle'.\n\n";
}

sub get_artist_by_cd {
    my $cdtitle = shift;
    print "get_artist_by_cd($cdtitle):\n";
    my $rs = $schema->resultset('Artist')->search(
        {
            'cds.title' => $cdtitle
        },
        {
            join     => [qw/ cds /],
        }
    );
    my $artist = $rs->first;
    print $artist->name . " recorded the CD '$cdtitle'.\n\n";
}
