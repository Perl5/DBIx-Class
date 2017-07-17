BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;

use Test::More;

use DBICTest;
use B::Deparse;
use DBIx::Class::_Util 'perlstring';

my $schema = DBICTest->init_schema(no_deploy => 1);
my $infmap = [qw/
  single_track.cd.artist.name
  year
/];

is_same_src (
  ($schema->source ('CD')->_mk_row_parser({
    inflate_map => $infmap,
  }))[0],
  '$_ = [
    { year => $_->[1] },
    { single_track => ( ! defined( $_->[0]) )
      ? bless( [
        undef,
        { cd => [
          undef,
          { artist => [
            { name  => $_->[0] },
          ] },
        ] },
      ], __NBC__ )
      : [
        undef,
        { cd => [
          undef,
          { artist => [
            { name  => $_->[0] },
          ] },
        ] },
      ]
    },
  ] for @{$_[0]}',
  'Simple 1:1 descending non-collapsing parser',
);

$infmap = [qw/
  single_track.cd.artist.cds.tracks.title
  single_track.cd.artist.artistid
  year
  single_track.cd.artist.cds.cdid
  title
  artist
/];

is_same_src (
  ($schema->source ('CD')->_mk_row_parser({
    inflate_map => $infmap,
  }))[0],
  '$_ = [
    { artist => $_->[5], title => $_->[4], year => $_->[2] },
    {
      single_track => ( (! defined $_->[0] ) && (! defined $_->[1]) && (! defined $_->[3] ) )
        ? bless( [
          undef,
          {
            cd => [
              undef,
              {
                artist => [
                  { artistid => $_->[1] },
                  {
                    cds => ( (! defined $_->[0] ) && ( ! defined $_->[3] ) )
                      ? bless ([
                        { cdid => $_->[3] },
                        {
                          tracks => ( ! defined $_->[0] )
                            ? bless ( [{ title => $_->[0] }], __NBC__ )
                            : [{ title => $_->[0] }]
                        }
                      ], __NBC__)
                      : [
                        { cdid => $_->[3] },
                        {
                          tracks => ( ! defined $_->[0] )
                            ? bless ( [{ title => $_->[0] }], __NBC__ )
                            : [{ title => $_->[0] }]
                        }
                      ]
                  }
                ]
              }
            ]
          }
        ], __NBC__)
        : [
          undef,
          {
            cd => [
              undef,
              {
                artist => [
                  { artistid => $_->[1] },
                  {
                    cds => ( (! defined $_->[0] ) && ( ! defined $_->[3] ) )
                      ? bless ([
                        { cdid => $_->[3] },
                        {
                          tracks => ( ! defined $_->[0] )
                            ? bless ( [{ title => $_->[0] }], __NBC__ )
                            : [{ title => $_->[0] }]
                        }
                      ], __NBC__)
                      : [
                        { cdid => $_->[3] },
                        {
                          tracks => ( ! defined $_->[0] )
                            ? bless ( [{ title => $_->[0] }], __NBC__ )
                            : [{ title => $_->[0] }]
                        }
                      ]
                  }
                ]
              }
            ]
          }
        ]
    }
  ] for @{$_[0]}',
  '1:1 descending non-collapsing parser terminating with chained 1:M:M',
);

is_same_src (
  ($schema->source ('CD')->_mk_row_parser({
    prune_null_branches => 1,
    inflate_map => $infmap,
  }))[0],
  '$_ = [
    { artist => $_->[5], title => $_->[4], year => $_->[2] },
    {
      single_track => ( (! defined $_->[0] ) && (! defined $_->[1]) && (! defined $_->[3] ) ) ? undef : [
        undef,
        {
          cd => [
            undef,
            {
              artist => [
                { artistid => $_->[1] },
                {
                  cds => ( (! defined $_->[0] ) && ( ! defined $_->[3] ) ) ? undef : [
                    { cdid => $_->[3] },
                    {
                      tracks => ( ! defined $_->[0] ) ? undef : [
                        { title => $_->[0] },
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }
  ] for @{$_[0]}',
  '1:1 descending non-collapsing pruning parser terminating with chained 1:M:M',
);

is_same_src (
  ($schema->source ('CD')->_mk_row_parser({
    hri_style => 1,
    prune_null_branches => 1,
    inflate_map => $infmap,
  }))[0],
  '$_ = {
      artist => $_->[5], title => $_->[4], year => $_->[2],

      ( single_track => ( (! defined $_->[0] ) && (! defined $_->[1]) && (! defined $_->[3] ) )
        ? undef
        : {
            cd =>
              {
                artist => {
                    artistid => $_->[1],
                    ( cds => ( (! defined $_->[0] ) && ( ! defined $_->[3] ) )
                      ? undef
                      : {
                          cdid => $_->[3],
                          ( tracks => ( ! defined $_->[0] )
                            ? undef
                            : { title => $_->[0] }
                          )
                        }
                    )
                  }
              }
          }
      )
    } for @{$_[0]}',
  '1:1 descending non-collapsing HRI-direct parser terminating with chained 1:M:M',
);



is_deeply (
  ($schema->source('CD')->_resolve_collapse({ as => {map { $infmap->[$_] => $_ } 0 .. $#$infmap} })),
  {
    -identifying_columns => [ 4, 5 ],

    single_track => {
      -identifying_columns => [ 1, 4, 5 ],
      -is_optional => 1,
      -is_single => 1,

      cd => {
        -identifying_columns => [ 1, 4, 5 ],
        -is_single => 1,

        artist => {
          -identifying_columns => [ 1, 4, 5 ],
          -is_single => 1,

          cds => {
            -identifying_columns => [ 1, 3, 4, 5 ],
            -is_optional => 1,

            tracks => {
              -identifying_columns => [ 0, 1, 3, 4, 5 ],
              -is_optional => 1,
            },
          },
        },
      },
    },
  },
  'Correct collapse map for 1:1 descending chain terminating with chained 1:M:M'
);

is_same_src (
  ($schema->source ('CD')->_mk_row_parser({
    inflate_map => $infmap,
    collapse => 1,
  }))[0],
  ' my $rows_pos = 0;
    my ($result_pos, @collapse_idx, $cur_row_data, %cur_row_ids);

    while ($cur_row_data = (
      (
        $rows_pos >= 0
          and
        (
          $_[0][$rows_pos++]
            or
          ( ($rows_pos = -1), undef )
        )
      )
        or
      ( $_[1] and $_[1]->() )
    ) ) {


      # NULL checks
      # mandatory => { 4 => 1, 5 => 1 }
      # from_first_encounter => [ [ 1, 3, 0 ] ]
      #
      ( defined( $cur_row_data->[4] ) or $_[3]->{4} = 1 ),

      ( defined( $cur_row_data->[5] ) or $_[3]->{5} = 1 ),

      (
        ( not defined $cur_row_data->[1] )
        ? (
            ( not defined $cur_row_data->[3] )
              and
            ( not defined $cur_row_data->[0] )
              or
            ( $_[3]->{1} = 1 )
          )
      : ( not defined $cur_row_data->[3] )
        ? (
            ( not defined $cur_row_data->[0] )
              or
            ( $_[3]->{3} = 1 )
        )
      : ()
      ),

      ( keys %{$_[3]} and (
        ( @{$_[2]} = $cur_row_data ),
        ( $result_pos = 0 ),
        last
      ) ),


      ( @cur_row_ids{0,1,3,4,5} = (
        ( $cur_row_data->[0] // "\0NULL\xFF$rows_pos\xFF0\0" ),
        ( $cur_row_data->[1] // "\0NULL\xFF$rows_pos\xFF1\0" ),
        ( $cur_row_data->[3] // "\0NULL\xFF$rows_pos\xFF3\0" ),
        ( $cur_row_data->[4] ),
        ( $cur_row_data->[5] ),
      ) ),

      # a present cref in $_[1] implies lazy prefetch, implies a supplied stash in $_[2]
      ( $_[1] and $result_pos and ! $collapse_idx[0]{$cur_row_ids{4}}{$cur_row_ids{5}} and (unshift @{$_[2]}, $cur_row_data) and last ),

      # the rowdata itself for root node
      ( $collapse_idx[0]{$cur_row_ids{4}}{$cur_row_ids{5}} //= $_[0][$result_pos++] = [{ artist => $cur_row_data->[5], title => $cur_row_data->[4], year => $cur_row_data->[2] }] ),

      # prefetch data of single_track (placed in root)
      ( $collapse_idx[0]{$cur_row_ids{4}}{$cur_row_ids{5}}[1]{single_track} //= $collapse_idx[1]{$cur_row_ids{1}}{$cur_row_ids{4}}{$cur_row_ids{5}} = [] ),
      ( defined($cur_row_data->[1]) or bless( $collapse_idx[0]{$cur_row_ids{4}}{$cur_row_ids{5}}[1]{single_track}, __NBC__ ) ),

      # prefetch data of cd (placed in single_track)
      ( $collapse_idx[1]{$cur_row_ids{1}}{$cur_row_ids{4}}{$cur_row_ids{5}}[1]{cd} //= $collapse_idx[2]{$cur_row_ids{1}}{$cur_row_ids{4}}{$cur_row_ids{5}} = [] ),

      # prefetch data of artist ( placed in single_track->cd)
      ( $collapse_idx[2]{$cur_row_ids{1}}{$cur_row_ids{4}}{$cur_row_ids{5}}[1]{artist} //= $collapse_idx[3]{$cur_row_ids{1}}{$cur_row_ids{4}}{$cur_row_ids{5}} = [{ artistid => $cur_row_data->[1] }] ),

      # prefetch data of cds (if available)
      (
        (! $collapse_idx[4]{$cur_row_ids{1}}{$cur_row_ids{3}}{$cur_row_ids{4}}{$cur_row_ids{5}} )
          and
        push @{$collapse_idx[3]{$cur_row_ids{1}}{$cur_row_ids{4}}{$cur_row_ids{5}}[1]{cds}}, (
          $collapse_idx[4]{$cur_row_ids{1}}{$cur_row_ids{3}}{$cur_row_ids{4}}{$cur_row_ids{5}} = [{ cdid => $cur_row_data->[3] }]
        )
      ),
      ( defined($cur_row_data->[3]) or bless( $collapse_idx[3]{$cur_row_ids{1}}{$cur_row_ids{4}}{$cur_row_ids{5}}[1]{cds}, __NBC__ ) ),

      # prefetch data of tracks (if available)
      (
        (! $collapse_idx[5]{$cur_row_ids{0}}{$cur_row_ids{1}}{$cur_row_ids{3}}{$cur_row_ids{4}}{$cur_row_ids{5}} )
          and
        push @{$collapse_idx[4]{$cur_row_ids{1}}{$cur_row_ids{3}}{$cur_row_ids{4}}{$cur_row_ids{5}}[1]{tracks}}, (
          $collapse_idx[5]{$cur_row_ids{0}}{$cur_row_ids{1}}{$cur_row_ids{3}}{$cur_row_ids{4}}{$cur_row_ids{5}} = [{ title => $cur_row_data->[0] }]
        )
      ),
      ( defined($cur_row_data->[0]) or bless( $collapse_idx[4]{$cur_row_ids{1}}{$cur_row_ids{3}}{$cur_row_ids{4}}{$cur_row_ids{5}}[1]{tracks}, __NBC__ ) ),

    }
    $#{$_[0]} = $result_pos - 1;
  ',
  'Same 1:1 descending terminating with chained 1:M:M but with collapse',
);

is_same_src (
  ($schema->source ('CD')->_mk_row_parser({
    inflate_map => $infmap,
    collapse => 1,
    hri_style => 1,
    prune_null_branches => 1,
  }))[0],
  ' my $rows_pos = 0;
    my ($result_pos, @collapse_idx, $cur_row_data, %cur_row_ids);

    while ($cur_row_data = (
      (
        $rows_pos >= 0
          and
        (
          $_[0][$rows_pos++]
            or
          ( ($rows_pos = -1), undef )
        )
      )
        or
      ( $_[1] and $_[1]->() )
    ) ) {


      # NULL checks
      # mandatory => { 4 => 1, 5 => 1 }
      # from_first_encounter => [ [ 1, 3, 0 ] ]
      #
      ( defined( $cur_row_data->[4] ) or $_[3]->{4} = 1 ),

      ( defined( $cur_row_data->[5] ) or $_[3]->{5} = 1 ),

      (
        ( not defined $cur_row_data->[1] )
        ? (
          ( not defined $cur_row_data->[3] )
            and
          ( not defined $cur_row_data->[0] )
            or
          ( $_[3]->{1} = 1 )
        )
      : ( not defined $cur_row_data->[3] )
        ? (
          ( not defined $cur_row_data->[0] )
            or
          ( $_[3]->{3} = 1 )
        )
      : ()
      ),

      ( keys %{$_[3]} and (
        ( @{$_[2]} = $cur_row_data ),
        ( $result_pos = 0 ),
        last
      ) ),


      ( @cur_row_ids{0, 1, 3, 4, 5} = @{$cur_row_data}[0, 1, 3, 4, 5] ),

      # a present cref in $_[1] implies lazy prefetch, implies a supplied stash in $_[2]
      ( $_[1] and $result_pos and ! $collapse_idx[0]{$cur_row_ids{4}}{$cur_row_ids{5}} and (unshift @{$_[2]}, $cur_row_data) and last ),

      # the rowdata itself for root node
      ( $collapse_idx[0]{$cur_row_ids{4}}{$cur_row_ids{5}} //= $_[0][$result_pos++] = { artist => $cur_row_data->[5], title => $cur_row_data->[4], year => $cur_row_data->[2] } ),

      # prefetch data of single_track (placed in root)
      ( (! defined($cur_row_data->[1]) ) ? $collapse_idx[0]{$cur_row_ids{4}}{$cur_row_ids{5}}{single_track} = undef : do {
        ( $collapse_idx[0]{$cur_row_ids{4}}{$cur_row_ids{5}}{single_track} //= $collapse_idx[1]{$cur_row_ids{1}}{$cur_row_ids{4}}{$cur_row_ids{5}} = {} ),

        # prefetch data of cd (placed in single_track)
        ( $collapse_idx[1]{$cur_row_ids{1}}{$cur_row_ids{4}}{$cur_row_ids{5}}{cd} //= $collapse_idx[2]{$cur_row_ids{1}}{$cur_row_ids{4}}{$cur_row_ids{5}} = {} ),

        # prefetch data of artist ( placed in single_track->cd)
        ( $collapse_idx[2]{$cur_row_ids{1}}{$cur_row_ids{4}}{$cur_row_ids{5}}{artist} //= $collapse_idx[3]{$cur_row_ids{1}}{$cur_row_ids{4}}{$cur_row_ids{5}} = { artistid => $cur_row_data->[1] } ),

        # prefetch data of cds (if available)
        ( (! defined $cur_row_data->[3] ) ? $collapse_idx[3]{$cur_row_ids{1}}{$cur_row_ids{4}}{$cur_row_ids{5}}{cds} = [] : do {

          (
            (! $collapse_idx[4]{$cur_row_ids{1}}{$cur_row_ids{3}}{$cur_row_ids{4}}{$cur_row_ids{5}} )
              and
            push @{$collapse_idx[3]{$cur_row_ids{1}}{$cur_row_ids{4}}{$cur_row_ids{5}}{cds}}, (
              $collapse_idx[4]{$cur_row_ids{1}}{$cur_row_ids{3}}{$cur_row_ids{4}}{$cur_row_ids{5}} = { cdid => $cur_row_data->[3] }
            )
          ),

          # prefetch data of tracks (if available)
          (( ! defined $cur_row_data->[0] ) ? $collapse_idx[4]{$cur_row_ids{1}}{$cur_row_ids{3}}{$cur_row_ids{4}}{$cur_row_ids{5}}{tracks} = [] : do {

            (
              (! $collapse_idx[5]{$cur_row_ids{0}}{$cur_row_ids{1}}{$cur_row_ids{3}}{$cur_row_ids{4}}{$cur_row_ids{5}} )
                and
              push @{$collapse_idx[4]{$cur_row_ids{1}}{$cur_row_ids{3}}{$cur_row_ids{4}}{$cur_row_ids{5}}{tracks}}, (
                $collapse_idx[5]{$cur_row_ids{0}}{$cur_row_ids{1}}{$cur_row_ids{3}}{$cur_row_ids{4}}{$cur_row_ids{5}} = { title => $cur_row_data->[0] }
              )
            ),
          } ),
        } ),
      } ),
    }
    $#{$_[0]} = $result_pos - 1;
  ',
  'Same 1:1 descending terminating with chained 1:M:M but with collapse, HRI-direct',
);

$infmap = [qw/
  tracks.lyrics.existing_lyric_versions.text
  existing_single_track.cd.artist.artistid
  existing_single_track.cd.artist.cds.year
  year
  genreid
  tracks.title
  existing_single_track.cd.artist.cds.cdid
  latest_cd
  existing_single_track.cd.artist.cds.tracks.title
  existing_single_track.cd.artist.cds.genreid
  tracks.lyrics.existing_lyric_versions.lyric_id
/];

is_deeply (
  $schema->source('CD')->_resolve_collapse({ as => {map { $infmap->[$_] => $_ } 0 .. $#$infmap} }),
  {
    -identifying_columns => [ 1 ], # existing_single_track.cd.artist.artistid

    existing_single_track => {
      -identifying_columns => [ 1 ], # existing_single_track.cd.artist.artistid
      -is_single => 1,

      cd => {
        -identifying_columns => [ 1 ], # existing_single_track.cd.artist.artistid
        -is_single => 1,

        artist => {
          -identifying_columns => [ 1 ], # existing_single_track.cd.artist.artistid
          -is_single => 1,

          cds => {
            -identifying_columns => [ 1, 6 ], # existing_single_track.cd.artist.cds.cdid
            -is_optional => 1,

            tracks => {
              -identifying_columns => [ 1, 6, 8 ], # existing_single_track.cd.artist.cds.cdid, existing_single_track.cd.artist.cds.tracks.title
              -is_optional => 1,
            }
          }
        }
      }
    },
    tracks => {
      -identifying_columns => [ 1, 5 ], # existing_single_track.cd.artist.artistid, tracks.title
      -is_optional => 1,

      lyrics => {
        -identifying_columns => [ 1, 5, 10 ], # existing_single_track.cd.artist.artistid, tracks.title, tracks.lyrics.existing_lyric_versions.lyric_id
        -is_single => 1,
        -is_optional => 1,

        existing_lyric_versions => {
          -identifying_columns => [ 0, 1, 5, 10 ], # tracks.lyrics.existing_lyric_versions.text, existing_single_track.cd.artist.artistid, tracks.title, tracks.lyrics.existing_lyric_versions.lyric_id
        },
      },
    }
  },
  'Correct collapse map constructed',
);

is_same_src (
  ($schema->source ('CD')->_mk_row_parser({
    inflate_map => $infmap,
    collapse => 1,
  }))[0],
  ' my $rows_pos = 0;
    my ($result_pos, @collapse_idx, $cur_row_data, %cur_row_ids);

    while ($cur_row_data = (
      (
        $rows_pos >= 0
          and
        (
          $_[0][$rows_pos++]
            or
          ( ($rows_pos = -1), undef )
        )
      )
        or
      ( $_[1] and $_[1]->() )
    ) ) {


      # NULL checks
      # mandatory => { 1 => 1 }
      # from_first_encounter => [ [6, 8], [5, 10, 0] ],
      #
      ( defined( $cur_row_data->[1] ) or $_[3]->{1} = 1 ),

      (
        ( not defined $cur_row_data->[6] )
        ? (
          ( not defined $cur_row_data->[8] )
            or
          ( $_[3]->{6} = 1 )
        )
      : ()
      ),

      (
        ( not defined $cur_row_data->[5] )
        ? (
          ( not defined $cur_row_data->[10] )
            and
          ( not defined $cur_row_data->[0] )
            or
          ( $_[3]->{5} = 1 )
          )
      : ( not defined $cur_row_data->[10] )
        ? (
          ( not defined $cur_row_data->[0] )
            or
          ( $_[3]->{10} = 1 )
        )
      : ()
      ),

      ( keys %{$_[3]} and (
        ( @{$_[2]} = $cur_row_data ),
        ( $result_pos = 0 ),
        last
      ) ),


      ( @cur_row_ids{0, 1, 5, 6, 8, 10} = (
        $cur_row_data->[0] // "\0NULL\xFF$rows_pos\xFF0\0",
        $cur_row_data->[1],
        $cur_row_data->[5] // "\0NULL\xFF$rows_pos\xFF5\0",
        $cur_row_data->[6] // "\0NULL\xFF$rows_pos\xFF6\0",
        $cur_row_data->[8] // "\0NULL\xFF$rows_pos\xFF8\0",
        $cur_row_data->[10] // "\0NULL\xFF$rows_pos\xFF10\0",
      ) ),

      # a present cref in $_[1] implies lazy prefetch, implies a supplied stash in $_[2]
      ( $_[1] and $result_pos and ! $collapse_idx[0]{$cur_row_ids{1}} and (unshift @{$_[2]}, $cur_row_data) and last ),

      ( $collapse_idx[0]{$cur_row_ids{1}} //= $_[0][$result_pos++] = [{ genreid => $cur_row_data->[4], latest_cd => $cur_row_data->[7], year => $cur_row_data->[3] }] ),

      ( $collapse_idx[0]{$cur_row_ids{1}}[1]{existing_single_track} //= $collapse_idx[1]{$cur_row_ids{1}} = [] ),
      ( $collapse_idx[1]{$cur_row_ids{1}}[1]{cd} //= $collapse_idx[2]{$cur_row_ids{1}} = [] ),
      ( $collapse_idx[2]{$cur_row_ids{1}}[1]{artist} //= $collapse_idx[3]{$cur_row_ids{1}} = [{ artistid => $cur_row_data->[1] }] ),

      (
        (! $collapse_idx[4]{$cur_row_ids{1}}{$cur_row_ids{6}} )
          and
        push @{ $collapse_idx[3]{$cur_row_ids{1}}[1]{cds} }, (
          $collapse_idx[4]{$cur_row_ids{1}}{$cur_row_ids{6}} = [{ cdid => $cur_row_data->[6], genreid => $cur_row_data->[9], year => $cur_row_data->[2] }]
        )
      ),
      ( defined($cur_row_data->[6]) or bless( $collapse_idx[3]{$cur_row_ids{1}}[1]{cds}, __NBC__ ) ),

      (
        (! $collapse_idx[5]{$cur_row_ids{1}}{$cur_row_ids{6}}{$cur_row_ids{8}} )
          and
        push @{ $collapse_idx[4]{$cur_row_ids{1}}{$cur_row_ids{6}}[1]{tracks} }, (
          $collapse_idx[5]{$cur_row_ids{1}}{$cur_row_ids{6}}{$cur_row_ids{8}} = [{ title => $cur_row_data->[8] }]
        )
      ),
      ( defined($cur_row_data->[8]) or bless( $collapse_idx[4]{$cur_row_ids{1}}{$cur_row_ids{6}}[1]{tracks}, __NBC__ ) ),

      (
        (! $collapse_idx[6]{$cur_row_ids{1}}{$cur_row_ids{5}} )
          and
        push @{ $collapse_idx[0]{$cur_row_ids{1}}[1]{tracks} }, (
          $collapse_idx[6]{$cur_row_ids{1}}{$cur_row_ids{5}} = [{ title => $cur_row_data->[5] }]
        )
      ),
      ( defined($cur_row_data->[5]) or bless( $collapse_idx[0]{$cur_row_ids{1}}[1]{tracks}, __NBC__ ) ),

      ( $collapse_idx[6]{$cur_row_ids{1}}{$cur_row_ids{5}}[1]{lyrics} //= $collapse_idx[7]{$cur_row_ids{1}}{$cur_row_ids{5}}{$cur_row_ids{10}} = [] ),
      ( defined($cur_row_data->[10]) or bless( $collapse_idx[6]{$cur_row_ids{1}}{$cur_row_ids{5}}[1]{lyrics}, __NBC__ ) ),

      (
        (! $collapse_idx[8]{$cur_row_ids{0}}{$cur_row_ids{1}}{$cur_row_ids{5}}{$cur_row_ids{10}} )
          and
        push @{ $collapse_idx[7]{$cur_row_ids{1}}{$cur_row_ids{5}}{$cur_row_ids{10}}[1]{existing_lyric_versions} }, (
          $collapse_idx[8]{$cur_row_ids{0}}{$cur_row_ids{1}}{$cur_row_ids{5}}{$cur_row_ids{10}} = [{ lyric_id => $cur_row_data->[10], text => $cur_row_data->[0] }]
        )
      ),
    }

    $#{$_[0]} = $result_pos - 1;
  ',
  'Multiple has_many on multiple branches torture test',
);

is_same_src (
  ($schema->source ('CD')->_mk_row_parser({
    inflate_map => $infmap,
    collapse => 1,
    prune_null_branches => 1,
  }))[0],
  ' my $rows_pos = 0;
    my ($result_pos, @collapse_idx, $cur_row_data, %cur_row_ids);

    while ($cur_row_data = (
      (
        $rows_pos >= 0
          and
        (
          $_[0][$rows_pos++]
            or
          ( ($rows_pos = -1), undef )
        )
      )
        or
      ( $_[1] and $_[1]->() )
    ) ) {


      # NULL checks
      # mandatory => { 1 => 1 }
      # from_first_encounter => [ [6, 8], [5, 10, 0] ],
      #
      ( defined( $cur_row_data->[1] ) or $_[3]->{1} = 1 ),

      (
        ( not defined $cur_row_data->[6] )
        ? (
          ( not defined $cur_row_data->[8] )
            or
          ( $_[3]->{6} = 1 )
        )
      : ()
      ),

      (
        ( not defined $cur_row_data->[5] )
        ? (
          ( not defined $cur_row_data->[10] )
            and
          ( not defined $cur_row_data->[0] )
            or
          ( $_[3]->{5} = 1 )
          )
      : ( not defined $cur_row_data->[10] )
        ? (
          ( not defined $cur_row_data->[0] )
            or
          ( $_[3]->{10} = 1 )
        )
      : ()
      ),

      ( keys %{$_[3]} and (
        ( @{$_[2]} = $cur_row_data ),
        ( $result_pos = 0 ),
        last
      ) ),


      ( @cur_row_ids{( 0, 1, 5, 6, 8, 10 )} = @{$cur_row_data}[( 0, 1, 5, 6, 8, 10 )] ),

      # a present cref in $_[1] implies lazy prefetch, implies a supplied stash in $_[2]
      ( $_[1] and $result_pos and ! $collapse_idx[0]{$cur_row_ids{1}} and (unshift @{$_[2]}, $cur_row_data) and last ),

      ( $collapse_idx[0]{$cur_row_ids{1}} //= $_[0][$result_pos++] = [{ genreid => $cur_row_data->[4], latest_cd => $cur_row_data->[7], year => $cur_row_data->[3] }] ),

      ( $collapse_idx[0]{$cur_row_ids{1}}[1]{existing_single_track} //= $collapse_idx[1]{$cur_row_ids{1}} = [] ),
      ( $collapse_idx[1]{$cur_row_ids{1}}[1]{cd} //= $collapse_idx[2]{$cur_row_ids{1}} = [] ),
      ( $collapse_idx[2]{$cur_row_ids{1}}[1]{artist} //= $collapse_idx[3]{$cur_row_ids{1}} = [{ artistid => $cur_row_data->[1] }] ),

      ( (! defined($cur_row_data->[6])) ? $collapse_idx[3]{$cur_row_ids{1}}[1]{cds} = [] : do {
        (
          (! $collapse_idx[4]{$cur_row_ids{1}}{$cur_row_ids{6}} )
            and
          push @{ $collapse_idx[3]{$cur_row_ids{1}}[1]{cds} }, (
            $collapse_idx[4]{$cur_row_ids{1}}{$cur_row_ids{6}} = [{ cdid => $cur_row_data->[6], genreid => $cur_row_data->[9], year => $cur_row_data->[2] }]
          )
        ),

        ( (! defined($cur_row_data->[8]) ) ? $collapse_idx[4]{$cur_row_ids{1}}{$cur_row_ids{6}}[1]{tracks} = [] : do {
          (
            (! $collapse_idx[5]{$cur_row_ids{1}}{$cur_row_ids{6}}{$cur_row_ids{8}} )
              and
            push @{ $collapse_idx[4]{$cur_row_ids{1}}{$cur_row_ids{6}}[1]{tracks} }, (
              $collapse_idx[5]{$cur_row_ids{1}}{$cur_row_ids{6}}{$cur_row_ids{8}} = [{ title => $cur_row_data->[8] }]
            )
          ),
        } ),
      } ),

      ( (! defined($cur_row_data->[5]) ) ? $collapse_idx[0]{$cur_row_ids{1}}[1]{tracks} = [] : do {

        (
          (! $collapse_idx[6]{$cur_row_ids{1}}{$cur_row_ids{5}} )
            and
          push @{ $collapse_idx[0]{$cur_row_ids{1}}[1]{tracks} }, (
            $collapse_idx[6]{$cur_row_ids{1}}{$cur_row_ids{5}} = [{ title => $cur_row_data->[5] }]
          )
        ),

        ( (! defined($cur_row_data->[10]) ) ? $collapse_idx[6]{$cur_row_ids{1}}{$cur_row_ids{5}}[1]{lyrics} = [] : do {

          ( $collapse_idx[6]{$cur_row_ids{1}}{$cur_row_ids{5}}[1]{lyrics} //= $collapse_idx[7]{$cur_row_ids{1}}{$cur_row_ids{5}}{$cur_row_ids{10}} = [] ),

          (
            (! $collapse_idx[8]{$cur_row_ids{0}}{$cur_row_ids{1}}{$cur_row_ids{5}}{$cur_row_ids{10}} )
              and
            push @{ $collapse_idx[7]{$cur_row_ids{1}}{$cur_row_ids{5}}{$cur_row_ids{10}}[1]{existing_lyric_versions} }, (
              $collapse_idx[8]{$cur_row_ids{0}}{$cur_row_ids{1}}{$cur_row_ids{5}}{$cur_row_ids{10}} = [{ lyric_id => $cur_row_data->[10], text => $cur_row_data->[0] }]
            )
          ),
        } ),
      } ),
    }

    $#{$_[0]} = $result_pos - 1;
  ',
  'Multiple has_many on multiple branches with branch pruning torture test',
);

$infmap = [
  'single_track.trackid',                   # (0) definitive link to root from 1:1:1:1:M:M chain
  'year',                                   # (1) non-unique
  'tracks.cd',                              # (2) \ together both uniqueness for second multirel
  'tracks.title',                           # (3) / and definitive link back to root
  'single_track.cd.artist.cds.cdid',        # (4) to give uniquiness to ...tracks.title below
  'single_track.cd.artist.cds.year',        # (5) non-unique
  'single_track.cd.artist.artistid',        # (6) uniqufies entire parental chain
  'single_track.cd.artist.cds.genreid',     # (7) nullable
  'single_track.cd.artist.cds.tracks.title',# (8) unique when combined with ...cds.cdid above
];

is_deeply (
  $schema->source('CD')->_resolve_collapse({ as => {map { $infmap->[$_] => $_ } 0 .. $#$infmap} }),
  {
    -identifying_columns => [],
    -identifying_columns_variants => [
      [ 0 ], [ 2 ],
    ],
    single_track => {
      -identifying_columns => [ 0 ],
      -is_optional => 1,
      -is_single => 1,
      cd => {
        -identifying_columns => [ 0 ],
        -is_single => 1,
        artist => {
          -identifying_columns => [ 0 ],
          -is_single => 1,
          cds => {
            -identifying_columns => [ 0, 4 ],
            -is_optional => 1,
            tracks => {
              -identifying_columns => [ 0, 4, 8 ],
              -is_optional => 1,
            }
          }
        }
      }
    },
    tracks => {
      -identifying_columns => [ 2, 3 ],
      -is_optional => 1,
    }
  },
  'Correct underdefined root collapse map constructed'
);

is_same_src (
  ($schema->source ('CD')->_mk_row_parser({
    inflate_map => $infmap,
    collapse => 1,
  }))[0],
  ' my $rows_pos = 0;
    my ($result_pos, @collapse_idx, $cur_row_data, %cur_row_ids);

    while ($cur_row_data = (
      (
        $rows_pos >= 0
          and
        (
          $_[0][$rows_pos++]
            or
          ( ($rows_pos = -1), undef )
        )
      )
        or
      ( $_[1] and $_[1]->() )
    ) ) {


      # NULL checks
      #
      # from_first_encounter => [ [0, 4, 8] ]
      # all_or_nothing => [ { 2 => 1, 3 => 1 } ]
      (
        ( not defined $cur_row_data->[0] )
        ? (
          ( not defined $cur_row_data->[4] )
            and
          ( not defined $cur_row_data->[8] )
            or
          ( $_[3]->{0} = 1 )
          )
      : ( not defined $cur_row_data->[4] )
        ? (
          ( not defined $cur_row_data->[8] )
            or
          ( $_[3]->{4} = 1 )
        )
      : ()
      ),

      (
        (
          ( not defined $cur_row_data->[2] )
            and
          ( not defined $cur_row_data->[3] )
        )
          or
        (
          ( defined($cur_row_data->[2]) or $_[3]->{2} = 1 ),
          ( defined($cur_row_data->[3]) or $_[3]->{3} = 1 ),
        )
      ),

      ( keys %{$_[3]} and (
        ( @{$_[2]} = $cur_row_data ),
        ( $result_pos = 0 ),
        last
      ) ),


      ( @cur_row_ids{( 0, 2, 3, 4, 8 )} = (
        $cur_row_data->[0] // "\0NULL\xFF$rows_pos\xFF0\0",
        $cur_row_data->[2] // "\0NULL\xFF$rows_pos\xFF2\0",
        $cur_row_data->[3] // "\0NULL\xFF$rows_pos\xFF3\0",
        $cur_row_data->[4] // "\0NULL\xFF$rows_pos\xFF4\0",
        $cur_row_data->[8] // "\0NULL\xFF$rows_pos\xFF8\0",
      )),

      # cache expensive set of ops in a non-existent rowid slot
      ( $cur_row_ids{10} = (
        ( ( defined $cur_row_data->[0] ) && (join "\xFF", q{}, $cur_row_ids{0}, q{} ))
          or
        ( ( defined $cur_row_data->[2] ) && (join "\xFF", q{}, $cur_row_ids{2}, q{} ))
          or
        "\0$rows_pos\0"
      )),

      # a present cref in $_[1] implies lazy prefetch, implies a supplied stash in $_[2]
      ( $_[1] and $result_pos and ! $collapse_idx[0]{$cur_row_ids{10}} and (unshift @{$_[2]}, $cur_row_data) and last ),

      ( $collapse_idx[0]{$cur_row_ids{10}} //= $_[0][$result_pos++] = [{ year => $$cur_row_data[1] }] ),

      ( $collapse_idx[0]{$cur_row_ids{10}}[1]{single_track} //= ($collapse_idx[1]{$cur_row_ids{0}} = [{ trackid => $cur_row_data->[0] }]) ),
      ( defined($cur_row_data->[0]) or bless ( $collapse_idx[0]{$cur_row_ids{10}}[1]{single_track}, __NBC__ ) ),

      ( $collapse_idx[1]{$cur_row_ids{0}}[1]{cd} //= $collapse_idx[2]{$cur_row_ids{0}} = [] ),

      ( $collapse_idx[2]{$cur_row_ids{0}}[1]{artist} //= ($collapse_idx[3]{$cur_row_ids{0}} = [{ artistid => $cur_row_data->[6] }]) ),

      (
        (! $collapse_idx[4]{$cur_row_ids{0}}{$cur_row_ids{4}} )
          and
        push @{$collapse_idx[3]{$cur_row_ids{0}}[1]{cds}}, (
          $collapse_idx[4]{$cur_row_ids{0}}{$cur_row_ids{4}} = [{ cdid => $cur_row_data->[4], genreid => $cur_row_data->[7], year => $cur_row_data->[5] }]
        )
      ),
      ( defined($cur_row_data->[4]) or bless ( $collapse_idx[3]{$cur_row_ids{0}}[1]{cds}, __NBC__ ) ),

      (
        (! $collapse_idx[5]{$cur_row_ids{0}}{$cur_row_ids{4}}{$cur_row_ids{8}} )
          and
        push @{$collapse_idx[4]{$cur_row_ids{0}}{$cur_row_ids{4}}[1]{tracks}}, (
            $collapse_idx[5]{$cur_row_ids{0}}{$cur_row_ids{4}}{$cur_row_ids{8}} = [{ title => $cur_row_data->[8] }]
        )
      ),
      ( defined($cur_row_data->[8]) or bless ( $collapse_idx[4]{$cur_row_ids{0}}{$cur_row_ids{4}}[1]{tracks}, __NBC__ ) ),

      (
        (! $collapse_idx[6]{$cur_row_ids{2}}{$cur_row_ids{3}} )
          and
        push @{$collapse_idx[0]{$cur_row_ids{10}}[1]{tracks}}, (
          $collapse_idx[6]{$cur_row_ids{2}}{$cur_row_ids{3}} = [{ cd => $$cur_row_data[2], title => $cur_row_data->[3] }]
        )
      ),
      ( defined($cur_row_data->[2]) or bless ( $collapse_idx[0]{$cur_row_ids{10}}[1]{tracks}, __NBC__ ) ),
    }

    $#{$_[0]} = $result_pos - 1;
  ',
  'Multiple has_many on multiple branches with underdefined root torture test',
);

is_same_src (
  ($schema->source ('CD')->_mk_row_parser({
    inflate_map => $infmap,
    collapse => 1,
    hri_style => 1,
    prune_null_branches => 1,
  }))[0],
  ' my $rows_pos = 0;
    my ($result_pos, @collapse_idx, $cur_row_data, %cur_row_ids);

    while ($cur_row_data = (
      (
        $rows_pos >= 0
          and
        (
          $_[0][$rows_pos++]
            or
          ( ($rows_pos = -1), undef )
        )
      )
        or
      ( $_[1] and $_[1]->() )
    ) ) {


      # NULL checks
      #
      # from_first_encounter => [ [0, 4, 8] ]
      # all_or_nothing => [ { 2 => 1, 3 => 1 } ]
      (
        ( not defined $cur_row_data->[0] )
        ? (
          ( not defined $cur_row_data->[4] )
            and
          ( not defined $cur_row_data->[8] )
            or
          ( $_[3]->{0} = 1 )
          )
      : ( not defined $cur_row_data->[4] )
        ? (
          ( not defined $cur_row_data->[8] )
            or
          ( $_[3]->{4} = 1 )
        )
      : ()
      ),

      (
        (
          ( not defined $cur_row_data->[2] )
            and
          ( not defined $cur_row_data->[3] )
        )
          or
        (
          ( defined($cur_row_data->[2]) or $_[3]->{2} = 1 ),
          ( defined($cur_row_data->[3]) or $_[3]->{3} = 1 ),
        )
      ),

      ( keys %{$_[3]} and (
        ( @{$_[2]} = $cur_row_data ),
        ( $result_pos = 0 ),
        last
      ) ),


      # do not care about nullability here
      ( @cur_row_ids{( 0, 2, 3, 4, 8 )} = @{$cur_row_data}[( 0, 2, 3, 4, 8 )] ),

      # cache expensive set of ops in a non-existent rowid slot
      ( $cur_row_ids{10} = (
        ( ( defined $cur_row_data->[0] ) && (join "\xFF", q{}, $cur_row_ids{0}, q{} ))
          or
        ( ( defined $cur_row_data->[2] ) && (join "\xFF", q{}, $cur_row_ids{2}, q{} ))
          or
        "\0$rows_pos\0"
      )),

      # a present cref in $_[1] implies lazy prefetch, implies a supplied stash in $_[2]
      ( $_[1] and $result_pos and ! $collapse_idx[0]{$cur_row_ids{10}} and (unshift @{$_[2]}, $cur_row_data) and last ),

      ( $collapse_idx[0]{$cur_row_ids{10}} //= $_[0][$result_pos++] = { year => $$cur_row_data[1] } ),

      ( (! defined $cur_row_data->[0] ) ? $collapse_idx[0]{$cur_row_ids{10}}{single_track} = undef : do {

        ( $collapse_idx[0]{$cur_row_ids{10}}{single_track} //= ($collapse_idx[1]{$cur_row_ids{0}} = { trackid => $$cur_row_data[0] }) ),

        ( $collapse_idx[1]{$cur_row_ids{0}}{cd} //= $collapse_idx[2]{$cur_row_ids{0}} = {} ),

        ( $collapse_idx[2]{$cur_row_ids{0}}{artist} //= ($collapse_idx[3]{$cur_row_ids{0}} = { artistid => $$cur_row_data[6] }) ),

        ( (! defined $cur_row_data->[4] ) ? $collapse_idx[3]{$cur_row_ids{0}}{cds} = [] : do {

          (
            (! $collapse_idx[4]{$cur_row_ids{0}}{$cur_row_ids{4}} )
              and
            push @{$collapse_idx[3]{$cur_row_ids{0}}{cds}}, (
                $collapse_idx[4]{$cur_row_ids{0}}{$cur_row_ids{4}} = { cdid => $$cur_row_data[4], genreid => $$cur_row_data[7], year => $$cur_row_data[5] }
            )
          ),

          ( (! defined $cur_row_data->[8] ) ? $collapse_idx[4]{$cur_row_ids{0}}{$cur_row_ids{4}}{tracks} = [] : do {

            (! $collapse_idx[5]{$cur_row_ids{0}}{$cur_row_ids{4}}{$cur_row_ids{8}} )
              and
            push @{$collapse_idx[4]{$cur_row_ids{0}}{$cur_row_ids{4}}{tracks}}, (
                $collapse_idx[5]{$cur_row_ids{0}}{$cur_row_ids{4}}{$cur_row_ids{8}} = { title => $$cur_row_data[8] }
            ),
          } ),
        } ),
      } ),

      ( (! defined $cur_row_data->[2] ) ? $collapse_idx[0]{$cur_row_ids{10}}{tracks} = [] : do {
        (
          (! $collapse_idx[6]{$cur_row_ids{2}}{$cur_row_ids{3}} )
            and
          push @{$collapse_idx[0]{$cur_row_ids{10}}{tracks}}, (
            $collapse_idx[6]{$cur_row_ids{2}}{$cur_row_ids{3}} = { cd => $$cur_row_data[2], title => $$cur_row_data[3] }
          )
        ),
      } ),
    }

    $#{$_[0]} = $result_pos - 1;
  ',
  'Multiple has_many on multiple branches with underdefined root, HRI-direct torture test',
);


$infmap = [
  'single_track.lyrics.track_id',             # (0) random optional 1:1:1 chain
  'year',                                     # (1) non-unique
  'tracks.cd',                                # (2) \ together both uniqueness for second multirel
  'tracks.title',                             # (3) / and definitive link back to root
  'single_track.cd.artist.cds.cdid',          # (4) to give uniquiness to ...tracks.title below
  'single_track.cd.artist.cds.year',          # (5) non-unique
  'single_track.cd.artist.artistid',          # (6) uniqufies entire parental chain
  'single_track.cd.artist.cds.genreid',       # (7) nullable
  'single_track.cd.artist.cds.tracks.title',  # (8) unique when combined with ...cds.cdid above
  'single_track.lyrics.lyric_versions.text',  # (9) unique combined with the single_track.lyrics 1:1:1
];

is_deeply (
  $schema->source('CD')->_resolve_collapse({ as => {map { $infmap->[$_] => $_ } 0 .. $#$infmap} }),
  {
    -identifying_columns => [],
    -identifying_columns_variants => [
      [ 2 ], [ 6 ],
    ],
    single_track => {
      -identifying_columns => [ 6 ],
      -is_optional => 1,
      -is_single => 1,
      cd => {
        -identifying_columns => [ 6 ],
        -is_single => 1,
        artist => {
          -identifying_columns => [ 6 ],
          -is_single => 1,
          cds => {
            -identifying_columns => [ 4, 6 ],
            -is_optional => 1,
            tracks => {
              -identifying_columns => [ 4, 6, 8 ],
              -is_optional => 1,
            }
          }
        }
      },
      lyrics => {
        -identifying_columns => [ 0, 6 ],
        -is_optional => 1,
        -is_single => 1,
        lyric_versions => {
          -identifying_columns => [ 0, 6, 9 ],
          -is_optional => 1,
        },
      },
    },
    tracks => {
      -identifying_columns => [ 2, 3 ],
      -is_optional => 1,
    }
  },
  'Correct underdefined root tripple-has-many-torture collapse map constructed'
);

is_same_src (
  ($schema->source ('CD')->_mk_row_parser({
    inflate_map => $infmap,
    collapse => 1,
    hri_style => 1,
    prune_null_branches => 1,
  }))[0],
  ' my $rows_pos = 0;
    my ($result_pos, @collapse_idx, $cur_row_data, %cur_row_ids);

    while ($cur_row_data = (
      (
        $rows_pos >= 0
          and
        (
          $_[0][$rows_pos++]
            or
          ( ($rows_pos = -1), undef )
        )
      )
        or
      ( $_[1] and $_[1]->() )
    ) ) {

      # NULL checks
      #
      # from_first_encounter => [ [6, 4, 8], [6, 0, 9] ]
      # all_or_nothing => [ { 2 => 1, 3 => 1 } ]
      (
        ( not defined $cur_row_data->[6] )
        ? (
          ( not defined $cur_row_data->[4] )
            and
          ( not defined $cur_row_data->[8] )
            or
          ( $_[3]->{6} = 1 )
          )
      : ( not defined $cur_row_data->[4] )
        ? (
          ( not defined $cur_row_data->[8] )
            or
          ( $_[3]->{4} = 1 )
          )
      : ()
      ),

      (
        ( not defined $cur_row_data->[6] )
        ? (
          ( not defined $cur_row_data->[0] )
            and
          ( not defined $cur_row_data->[9] )
            or
          ( $_[3]->{6} = 1 )
          )
      : ( not defined $cur_row_data->[0] )
        ? (
          ( not defined $cur_row_data->[9] )
            or
          ( $_[3]->{0} = 1 )
          )
      : ()
      ),

      (
        (
          ( not defined $cur_row_data->[2] )
            and
          ( not defined $cur_row_data->[3] )
        )
          or
        (
          ( defined($cur_row_data->[2]) or $_[3]->{2} = 1 ),
          ( defined($cur_row_data->[3]) or $_[3]->{3} = 1 ),
        )
      ),

      ( keys %{$_[3]} and (
        ( @{$_[2]} = $cur_row_data ),
        ( $result_pos = 0 ),
        last
      ) ),


      # do not care about nullability here
      ( @cur_row_ids{( 0, 2, 3, 4, 6, 8, 9 )} = @{$cur_row_data}[( 0, 2, 3, 4, 6, 8, 9 )] ),

      # cache expensive set of ops in a non-existent rowid slot
      ( $cur_row_ids{11} = (
        ( ( defined $cur_row_data->[2] ) && (join "\xFF", q{}, $cur_row_ids{2}, q{} ))
          or
        ( ( defined $cur_row_data->[6] ) && (join "\xFF", q{}, $cur_row_ids{6}, q{} ))
          or
        "\0$rows_pos\0"
      )),

      # a present cref in $_[1] implies lazy prefetch, implies a supplied stash in $_[2]
      ( $_[1] and $result_pos and ! $collapse_idx[0]{$cur_row_ids{11}} and (unshift @{$_[2]}, $cur_row_data) and last ),

      ( $collapse_idx[0]{$cur_row_ids{11}} //= $_[0][$result_pos++] = { year => $$cur_row_data[1] } ),

      ( (! defined $cur_row_data->[6] ) ? $collapse_idx[0]{$cur_row_ids{11}}{single_track} = undef : do {

        ( $collapse_idx[0]{$cur_row_ids{11}}{single_track} //= ( $collapse_idx[1]{$cur_row_ids{6}} = {} ) ),

        ( $collapse_idx[1]{$cur_row_ids{6}}{cd} //= $collapse_idx[2]{$cur_row_ids{6}} = {} ),

        ( $collapse_idx[2]{$cur_row_ids{6}}{artist} //= ($collapse_idx[3]{$cur_row_ids{6}} = { artistid => $$cur_row_data[6] }) ),

        ( (! defined $cur_row_data->[4] ) ? $collapse_idx[3]{$cur_row_ids{6}}{cds} = [] : do {

          (
            (! $collapse_idx[4]{$cur_row_ids{4}}{$cur_row_ids{6}} )
              and
            push @{$collapse_idx[3]{$cur_row_ids{6}}{cds}}, (
                $collapse_idx[4]{$cur_row_ids{4}}{$cur_row_ids{6}} = { cdid => $$cur_row_data[4], genreid => $$cur_row_data[7], year => $$cur_row_data[5] }
            )
          ),

          ( (! defined $cur_row_data->[8] ) ? $collapse_idx[4]{$cur_row_ids{4}}{$cur_row_ids{6}}{tracks} = [] : do {

            (! $collapse_idx[5]{$cur_row_ids{4}}{$cur_row_ids{6}}{$cur_row_ids{8}} )
              and
            push @{$collapse_idx[4]{$cur_row_ids{4}}{$cur_row_ids{6}}{tracks}}, (
                $collapse_idx[5]{$cur_row_ids{4}}{$cur_row_ids{6}}{$cur_row_ids{8}} = { title => $$cur_row_data[8] }
            ),
          } ),
        } ),

        ( ( ! defined $cur_row_data->[0] ) ? $collapse_idx[1]{ $cur_row_ids{6} }{"lyrics"} = undef : do {

          ( $collapse_idx[1]{ $cur_row_ids{6} }{"lyrics"} //= ( $collapse_idx[6]{ $cur_row_ids{0} }{ $cur_row_ids{6} } = { "track_id" => $cur_row_data->[0] } ) ),

          ( ( ! defined $cur_row_data->[9] ) ? $collapse_idx[6]{ $cur_row_ids{0} }{ $cur_row_ids{6} }{"lyric_versions"} = [] : do {
            (
              (! $collapse_idx[7]{ $cur_row_ids{0} }{ $cur_row_ids{6} }{ $cur_row_ids{9} })
                and
              push @{$collapse_idx[6]{ $cur_row_ids{0} }{ $cur_row_ids{6} }{"lyric_versions"}}, (
                $collapse_idx[7]{ $cur_row_ids{0} }{ $cur_row_ids{6} }{ $cur_row_ids{9} } = { "text" => $cur_row_data->[9] }
              ),
            ),
          } ),
        } ),
      } ),

      ( (! defined $cur_row_data->[2] ) ? $collapse_idx[0]{$cur_row_ids{11}}{tracks} = [] : do {
        (
          (! $collapse_idx[8]{$cur_row_ids{2}}{$cur_row_ids{3}} )
            and
          push @{$collapse_idx[0]{$cur_row_ids{11}}{tracks}}, (
            $collapse_idx[8]{$cur_row_ids{2}}{$cur_row_ids{3}} = { cd => $$cur_row_data[2], title => $$cur_row_data[3] }
          )
        ),
      } ),
    }

    $#{$_[0]} = $result_pos - 1;
  ',
  'Tripple multiple has_many on multiple branches with underdefined root, HRI-direct torture test',
);

is_same_src (
  ($schema->source ('Owners')->_mk_row_parser({
    inflate_map => [qw( books.title books.owner )],
    collapse => 1,
    prune_null_branches => 1,
  }))[0],
  ' my $rows_pos = 0;
    my ($result_pos, @collapse_idx, $cur_row_data, %cur_row_ids );

    while ($cur_row_data = (
      (
        $rows_pos >= 0
          and
        (
          $_[0][$rows_pos++]
            or
          ( ($rows_pos = -1), undef )
        )
      )
        or
      ( $_[1] and $_[1]->() )
    ) ) {

      ( @cur_row_ids{0,1} = @{$cur_row_data}[0,1] ),

      ( $cur_row_ids{3} = (
        ( ( defined $cur_row_data->[1] ) && (join "\xFF", q{}, $cur_row_ids{1}, q{} ))
          or
        "\0${rows_pos}\0"
      )),

      ( $_[1] and $result_pos and ! $collapse_idx[0]{$cur_row_ids{3}} and (unshift @{$_[2]}, $cur_row_data) and last ),

      # empty data for the root node
      ( $collapse_idx[0]{$cur_row_ids{3}} //= $_[0][$result_pos++] = [] ),

      ( ( ! defined $cur_row_data->[0] ) ? $collapse_idx[0]{$cur_row_ids{3}}[1]{"books"} = [] : do {
        ( ! $collapse_idx[1]{$cur_row_ids{0}} )
          and
        push @{$collapse_idx[0]{$cur_row_ids{3}}[1]{books}},
          $collapse_idx[1]{$cur_row_ids{0}} = [ { owner => $cur_row_data->[1], title => $cur_row_data->[0] } ]
      } ),
    }

    $#{$_[0]} = $result_pos - 1; # truncate the passed in array to where we filled it with results
  ',
  'Non-premultiplied implicit collapse with missing join columns',
);

is_same_src (
  ($schema->source('Artist')->_mk_row_parser({
    inflate_map => [qw( artistid cds.artist cds.title cds.tracks.title )],
    collapse => 1,
    prune_null_branches => 1,
  }))[0],
  ' my $rows_pos = 0;
    my ($result_pos, @collapse_idx, $cur_row_data, %cur_row_ids );

    while ($cur_row_data = (
      (
        $rows_pos >= 0
          and
        (
          $_[0][$rows_pos++]
            or
          ( ($rows_pos = -1), undef )
        )
      )
        or
      ( $_[1] and $_[1]->() )
    ) ) {

      # NULL checks
      #
      # mandatory => { 0 => 1 }
      # from_first_encounter => [ [1, 2, 3] ]
      # all_or_nothing => [ { 1 => 1, 2 => 1 } ]

      ( defined( $cur_row_data->[0] ) or $_[3]->{0} = 1 ),

      (
        ( not defined $cur_row_data->[1] )
        ? (
          ( not defined $cur_row_data->[2] )
            and
          ( not defined $cur_row_data->[3] )
            or
          $_[3]->{1} = 1
          )
      : ( not defined $cur_row_data->[2] )
        ? (
          ( not defined $cur_row_data->[3] )
            or
          $_[3]->{2} = 1
          )
      : ()
      ),

      (
        (
          ( not defined $cur_row_data->[1] )
            and
          ( not defined $cur_row_data->[2] )
        )
          or
        (
          ( defined($cur_row_data->[1]) or $_[3]->{1} = 1 ),
          ( defined($cur_row_data->[2]) or $_[3]->{2} = 1 ),
        )
      ),

      ( keys %{$_[3]} and (
        ( @{$_[2]} = $cur_row_data ),
        ( $result_pos = 0 ),
        last
      ) ),


      ( @cur_row_ids{( 0, 1, 2, 3 )} = @{$cur_row_data}[ 0, 1, 2, 3 ] ),

      ( $_[1] and $result_pos and ! $collapse_idx[0]{$cur_row_ids{0}} and (unshift @{$_[2]}, $cur_row_data) and last ),

      ( $collapse_idx[0]{ $cur_row_ids{0} }
          //= $_[0][$result_pos++] = [ { "artistid" => $cur_row_data->[0] } ]
      ),

      ( ( ! defined $cur_row_data->[1] ) ? $collapse_idx[0]{ $cur_row_ids{0} }[1]{"cds"} = [] : do {

        (
          ! $collapse_idx[1]{ $cur_row_ids{0} }{ $cur_row_ids{1} }{ $cur_row_ids{2} }
            and
          push @{$collapse_idx[0]{ $cur_row_ids{0} }[1]{"cds"}},
            $collapse_idx[1]{ $cur_row_ids{0} }{ $cur_row_ids{1} }{ $cur_row_ids{2} }
              = [ { "artist" => $cur_row_data->[1], "title" => $cur_row_data->[2] } ]
        ),

        ( ( ! defined $cur_row_data->[3] ) ? $collapse_idx[1]{ $cur_row_ids{0} }{ $cur_row_ids{1} }{ $cur_row_ids{2} }[1]{"tracks"} = [] : do {
          (
            ! $collapse_idx[2]{ $cur_row_ids{0} }{ $cur_row_ids{1} }{ $cur_row_ids{2} }{ $cur_row_ids{3} }
              and
            push @{$collapse_idx[1]{ $cur_row_ids{0} }{ $cur_row_ids{1} }{ $cur_row_ids{2} }[1]{"tracks"}},
              $collapse_idx[2]{ $cur_row_ids{0} }{ $cur_row_ids{1} }{ $cur_row_ids{2} }{ $cur_row_ids{3} }
                = [ { "title" => $cur_row_data->[3] } ]
          ),
        } ),
      } ),
    }

    $#{$_[0]} = $result_pos - 1
  ',
  'A rolled out version of inflate map of misled_rowparser.t'
);

done_testing;

my $deparser;
sub is_same_src { SKIP: {

  skip "Skipping comparison of unicode-poisoned source", 1
    if DBIx::Class::_ENV_::STRESSTEST_UTF8_UPGRADE_GENERATED_COLLAPSER_SOURCE;

  $deparser ||= B::Deparse->new;
  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my ($got, $expect) = @_;

  skip "Not testing equality of source containing defined-or operator on this perl $]", 1
    if ( "$]" < 5.010 and $expect =~ m!\Q//=! );

  $expect =~ s/__NBC__/perlstring($DBIx::Class::ResultSource::RowParser::Util::null_branch_class)/ge;

  $expect = "sub { use strict; use warnings FATAL => 'uninitialized';\n$expect\n  }";

  my @normalized = map {
    my $cref = eval "sub { $_ }" or do {
      fail "Coderef does not compile!\n\n$@\n\n$_";
      return undef;
    };
    $deparser->coderef2text($cref);
  } ($got, $expect);

  &is (@normalized, $_[2]||() ) or do {
    eval { require Test::Differences }
      ? &Test::Differences::eq_or_diff( @normalized, $_[2]||() )
      : note ("Original sources:\n\n$got\n\n$expect\n")
    ;
    exit 1;
  };
} }
