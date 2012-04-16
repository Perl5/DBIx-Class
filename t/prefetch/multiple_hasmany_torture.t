use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $mo_rs = $schema->resultset('Artist')->search(
    { 'me.artistid' => 4 },
    {
        prefetch     => [
            {
                cds => [
                    { tracks         => { cd_single => 'tracks' } },
                    { cd_to_producer => 'producer' }
                ]
            },
            { artwork_to_artist => 'artwork' }
        ],

        result_class => 'DBIx::Class::ResultClass::HashRefInflator',

        order_by => [qw/tracks.position tracks.trackid producer.producerid/],
    }
);

$schema->resultset('Artist')->create(
    {
        name => 'mo',
        rank => '1337',
        cds  => [
            {
                title  => 'Song of a Foo',
                year   => '1999',
                tracks => [
                    {
                        title    => 'Foo Me Baby One More Time',
                    },
                    {
                        title    => 'Foo Me Baby One More Time II',
                    },
                    {
                        title    => 'Foo Me Baby One More Time III',
                    },
                    {
                        title    => 'Foo Me Baby One More Time IV',
                        cd_single =>
                          { artist => 1, title => 'MO! Single', year => 2021, tracks => [
                            { title => 'singled out' }, { title => 'still alone' },
                          ] },
                    }
                ],
                cd_to_producer => [
                    { producer => { name => 'riba' } },
                    { producer => { name => 'sushi' } },
                ]
            },
            {
                title  => 'Song of a Foo II',
                year   => '2002',
                tracks => [
                    {
                        title    => 'Quit Playing Games With My Heart',
                    },
                    {
                        title    => 'Bar Foo',
                    },
                    {
                        title    => 'Foo Bar',
                        cd_single =>
                          { artist => 2, title => 'MO! Single', year => 2020, tracks => [
                            { title => 'singled out' }, { title => 'still alone' },
                          ] },
                    }
                ],
                cd_to_producer => [
                  { producer => { name => 'riba' } },
                  { producer => { name => 'sushi' } },
                ],
            }
        ],
        artwork_to_artist =>
          [ { artwork => { cd_id => 1 } }, { artwork => { cd_id => 2 } } ]
    }
);

my $mo = $mo_rs->next;

is( @{$mo->{cds}}, 2, 'two CDs' );

is_deeply(
    $mo,
    {
        'cds' => [
            {
                'single_track' => undef,
                'tracks'       => [
                    {
                        'cd'        => '6',
                        'position'  => '1',
                        'trackid'   => '19',
                        'title'     => 'Foo Me Baby One More Time',
                        'cd_single' => undef,
                        'last_updated_on' => undef,
                        'last_updated_at' => undef
                    },
                    {
                        'cd'              => '6',
                        'position'        => '2',
                        'trackid'         => '20',
                        'title'           => 'Foo Me Baby One More Time II',
                        'cd_single'       => undef,
                        'last_updated_on' => undef,
                        'last_updated_at' => undef
                    },
                    {
                        'cd'              => '6',
                        'position'        => '3',
                        'trackid'         => '21',
                        'title'           => 'Foo Me Baby One More Time III',
                        'cd_single'       => undef,
                        'last_updated_on' => undef,
                        'last_updated_at' => undef
                    },
                    {
                        'cd'              => '6',
                        'position'        => '4',
                        'trackid'         => '22',
                        'title'           => 'Foo Me Baby One More Time IV',
                        'last_updated_on' => undef,
                        'last_updated_at' => undef,
                        'cd_single' => {
                            'single_track' => '22',
                            'artist'       => '1',
                            'cdid'         => '7',
                            'title'        => 'MO! Single',
                            'genreid'      => undef,
                            'year'         => '2021',
                            'tracks'       => [
                                {
                                    'cd' => '7',
                                    'position' => '1',
                                    'title' => 'singled out',
                                    'trackid' => '23',
                                    'last_updated_at' => undef,
                                    'last_updated_on' => undef
                                },
                                {
                                    'cd' => '7',
                                    'position' => '2',
                                    'title' => 'still alone',
                                    'trackid' => '24',
                                    'last_updated_at' => undef,
                                    'last_updated_on' => undef
                                },
                            ],
                        },
                    }
                ],
                'artist'         => '4',
                'cdid'           => '6',
                'cd_to_producer' => [
                    {
                        'attribute' => undef,
                        'cd'        => '6',
                        'producer'  => {
                            'name'       => 'riba',
                            'producerid' => '4'
                        }
                    },
                    {
                        'attribute' => undef,
                        'cd'        => '6',
                        'producer'  => {
                            'name'       => 'sushi',
                            'producerid' => '5'
                        }
                    }
                ],
                'title'   => 'Song of a Foo',
                'genreid' => undef,
                'year'    => '1999'
            },
            {
                'single_track' => undef,
                'tracks'       => [
                    {
                        'cd'        => '8',
                        'position'  => '1',
                        'trackid'   => '25',
                        'title'     => 'Quit Playing Games With My Heart',
                        'last_updated_on' => undef,
                        'last_updated_at' => undef,
                        'cd_single'       => undef,
                    },
                    {
                        'cd'              => '8',
                        'position'        => '2',
                        'trackid'         => '26',
                        'title'           => 'Bar Foo',
                        'cd_single'       => undef,
                        'last_updated_on' => undef,
                        'last_updated_at' => undef
                    },
                    {
                        'cd'              => '8',
                        'position'        => '3',
                        'trackid'         => '27',
                        'title'           => 'Foo Bar',
                        'last_updated_on' => undef,
                        'last_updated_at' => undef,
                        'cd_single' => {
                            'single_track' => '27',
                            'artist'       => '2',
                            'cdid'         => '9',
                            'title'        => 'MO! Single',
                            'genreid'      => undef,
                            'year'         => '2020',
                            'tracks'       => [
                                {
                                    'cd' => '9',
                                    'position' => '1',
                                    'title' => 'singled out',
                                    'trackid' => '28',
                                    'last_updated_at' => undef,
                                    'last_updated_on' => undef
                                },
                                {
                                    'cd' => '9',
                                    'position' => '2',
                                    'title' => 'still alone',
                                    'trackid' => '29',
                                    'last_updated_at' => undef,
                                    'last_updated_on' => undef
                                },
                            ],

                          },
                      },
                ],
                'artist'         => '4',
                'cdid'           => '8',
                'cd_to_producer' => [
                    {
                        'attribute' => undef,
                        'cd'        => '8',
                        'producer'  => {
                            'name'       => 'riba',
                            'producerid' => '4'
                        }
                    },
                    {
                        'attribute' => undef,
                        'cd'        => '8',
                        'producer'  => {
                            'name'       => 'sushi',
                            'producerid' => '5'
                        }
                    }
                ],
                'title'   => 'Song of a Foo II',
                'genreid' => undef,
                'year'    => '2002'
            }
        ],
        'artistid'          => '4',
        'charfield'         => undef,
        'name'              => 'mo',
        'artwork_to_artist' => [
            {
                'artwork'       => { 'cd_id' => '1' },
                'artist_id'     => '4',
                'artwork_cd_id' => '1'
            },
            {
                'artwork'       => { 'cd_id' => '2' },
                'artist_id'     => '4',
                'artwork_cd_id' => '2'
            }
        ],
        'rank' => '1337'
    }
);

done_testing;
