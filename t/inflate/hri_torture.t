use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;

# More tests like this in t/prefetch/manual.t

my $schema = DBICTest->init_schema(no_populate => 1, quote_names => 1);
$schema->resultset('Artist')->create({ name => 'JMJ', cds => [{
  title => 'Magnetic Fields',
  year => 1981,
  genre => { name => 'electro' },
  tracks => [
    { title => 'm1' },
    { title => 'm2' },
    { title => 'm3' },
    { title => 'm4' },
  ],
} ] });


$schema->resultset('CD')->create({
  title => 'Equinoxe',
  year => 1978,
  artist => { name => 'JMJ' },
  genre => { name => 'electro' },
  tracks => [
    { title => 'e1' },
    { title => 'e2' },
    { title => 'e3' },
  ],
  single_track => {
    title => 'o1',
    cd => {
      title => 'Oxygene',
      year => 1976,
      artist => { name => 'JMJ' },
      tracks => [
        { title => 'o2', position => 2},  # the position should not be needed here, bug in MC
      ],
    },
  },
});

for (1,2) {
  $schema->resultset('CD')->create({ artist => 1, year => 1977, title => "fuzzy_$_" });
}

my $rs = $schema->resultset('CD');

is_deeply
  $rs->search({}, {
    columns => {
      year                          => 'me.year',
      'single_track.cd.artist.name' => 'artist.name',
    },
    join => { single_track => { cd => 'artist' } },
    order_by => [qw/me.cdid artist.artistid/],
  })->all_hri,
  [
    {
      single_track => undef,
      year => 1981
    },
    {
      single_track => undef,
      year => 1976
    },
    {
      single_track => {
        cd => {
          artist => {
            name => "JMJ"
          }
        }
      },
      year => 1978
    },
    {
      single_track => undef,
      year => 1977
    },
    {
      single_track => undef,
      year => 1977
    },
  ],
  'plain 1:1 descending chain'
;

is_deeply
  $rs->search({}, {
    columns => {
      'artist'                                  => 'me.artist',
      'title'                                   => 'me.title',
      'year'                                    => 'me.year',
      'single_track.cd.artist.artistid'         => 'artist.artistid',
      'single_track.cd.artist.cds.cdid'         => 'cds.cdid',
      'single_track.cd.artist.cds.tracks.title' => 'tracks.title',
    },
    join => { single_track => { cd => { artist => { cds => 'tracks' } } } },
    order_by => [qw/me.cdid artist.artistid cds.cdid tracks.trackid/],
  })->all_hri,
  [
    {
      artist => 1,
      single_track => undef,
      title => "Magnetic Fields",
      year => 1981
    },
    {
      artist => 1,
      single_track => undef,
      title => "Oxygene",
      year => 1976
    },
    {
      artist => 1,
      single_track => {
        cd => {
          artist => {
            artistid => 1,
            cds => {
              cdid => 1,
              tracks => {
                title => "m1"
              }
            }
          }
        }
      },
      title => "Equinoxe",
      year => 1978
    },
    {
      artist => 1,
      single_track => {
        cd => {
          artist => {
            artistid => 1,
            cds => {
              cdid => 1,
              tracks => {
                title => "m2"
              }
            }
          }
        }
      },
      title => "Equinoxe",
      year => 1978
    },
    {
      artist => 1,
      single_track => {
        cd => {
          artist => {
            artistid => 1,
            cds => {
              cdid => 1,
              tracks => {
                title => "m3"
              }
            }
          }
        }
      },
      title => "Equinoxe",
      year => 1978
    },
    {
      artist => 1,
      single_track => {
        cd => {
          artist => {
            artistid => 1,
            cds => {
              cdid => 1,
              tracks => {
                title => "m4"
              }
            }
          }
        }
      },
      title => "Equinoxe",
      year => 1978
    },
    {
      artist => 1,
      single_track => {
        cd => {
          artist => {
            artistid => 1,
            cds => {
              cdid => 2,
              tracks => {
                title => "o2"
              }
            }
          }
        }
      },
      title => "Equinoxe",
      year => 1978
    },
    {
      artist => 1,
      single_track => {
        cd => {
          artist => {
            artistid => 1,
            cds => {
              cdid => 2,
              tracks => {
                title => "o1"
              }
            }
          }
        }
      },
      title => "Equinoxe",
      year => 1978
    },
    {
      artist => 1,
      single_track => {
        cd => {
          artist => {
            artistid => 1,
            cds => {
              cdid => 3,
              tracks => {
                title => "e1"
              }
            }
          }
        }
      },
      title => "Equinoxe",
      year => 1978
    },
    {
      artist => 1,
      single_track => {
        cd => {
          artist => {
            artistid => 1,
            cds => {
              cdid => 3,
              tracks => {
                title => "e2"
              }
            }
          }
        }
      },
      title => "Equinoxe",
      year => 1978
    },
    {
      artist => 1,
      single_track => {
        cd => {
          artist => {
            artistid => 1,
            cds => {
              cdid => 3,
              tracks => {
                title => "e3"
              }
            }
          }
        }
      },
      title => "Equinoxe",
      year => 1978
    },
    {
      artist => 1,
      single_track => {
        cd => {
          artist => {
            artistid => 1,
            cds => {
              cdid => 4,
              tracks => undef
            }
          }
        }
      },
      title => "Equinoxe",
      year => 1978
    },
    {
      artist => 1,
      single_track => {
        cd => {
          artist => {
            artistid => 1,
            cds => {
              cdid => 5,
              tracks => undef
            }
          }
        }
      },
      title => "Equinoxe",
      year => 1978
    },
    {
      artist => 1,
      single_track => undef,
      title => "fuzzy_1",
      year => 1977
    },
    {
      artist => 1,
      single_track => undef,
      title => "fuzzy_2",
      year => 1977
    }
  ],
  'non-collapsing 1:1:1:M:M chain',
;

is_deeply
  $rs->search({}, {
    columns => {
      'artist'                                  => 'me.artist',
      'title'                                   => 'me.title',
      'year'                                    => 'me.year',
      'single_track.cd.artist.artistid'         => 'artist.artistid',
      'single_track.cd.artist.cds.cdid'         => 'cds.cdid',
      'single_track.cd.artist.cds.tracks.title' => 'tracks.title',
    },
    join => { single_track => { cd => { artist => { cds => 'tracks' } } } },
    order_by => [qw/me.cdid artist.artistid cds.cdid tracks.trackid/],
    collapse => {}, #hashref to keep older DBIC versions happy (doesn't actually work)
  })->all_hri,
  [
    {
      artist => 1,
      single_track => undef,
      title => "Magnetic Fields",
      year => 1981
    },
    {
      artist => 1,
      single_track => undef,
      title => "Oxygene",
      year => 1976
    },
    {
      artist => 1,
      single_track => {
        cd => {
          artist => {
            artistid => 1,
            cds => [
              {
                cdid => 1,
                tracks => [
                  {
                    title => "m1"
                  },
                  {
                    title => "m2"
                  },
                  {
                    title => "m3"
                  },
                  {
                    title => "m4"
                  }
                ]
              },
              {
                cdid => 2,
                tracks => [
                  {
                    title => "o2"
                  },
                  {
                    title => "o1"
                  }
                ]
              },
              {
                cdid => 3,
                tracks => [
                  {
                    title => "e1"
                  },
                  {
                    title => "e2"
                  },
                  {
                    title => "e3"
                  }
                ]
              },
              {
                cdid => 4,
                tracks => []
              },
              {
                cdid => 5,
                tracks => []
              }
            ]
          }
        }
      },
      title => "Equinoxe",
      year => 1978
    },
    {
      artist => 1,
      single_track => undef,
      title => "fuzzy_1",
      year => 1977
    },
    {
      artist => 1,
      single_track => undef,
      title => "fuzzy_2",
      year => 1977
    }
  ],
  'collapsing 1:1:1:M:M chain',
;

done_testing;
