use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;
use B::Deparse;

my $schema = DBICTest->init_schema(no_deploy => 1);
my $infmap = [qw/single_track.cd.artist.name year/];

is_same_src (
  $schema->source ('CD')->_mk_row_parser({
    inflate_map => $infmap,
  }),
  '$_ = [
    { year => $_->[1] },
    { single_track => [
      undef,
      { cd => [
        undef,
        { artist => [
          { name  => $_->[0] },
        ] },
      ]},
    ]},
  ] for @{$_[0]}',
  'Simple 1:1 descending non-collapsing parser',
);

$infmap = [qw/
  single_track.cd.artist.artistid
  year
  single_track.cd.artist.cds.tracks.title
  single_track.cd.artist.cds.cdid
  title
  artist
/];
is_same_src (
  $schema->source ('CD')->_mk_row_parser({
    inflate_map => $infmap,
  }),
  '$_ = [
    { artist => $_->[5], title => $_->[4], year => $_->[1] },
    { single_track => [
      undef,
      { cd => [
        undef,
        { artist => [
          { artistid => $_->[0] },
          { cds => [
            { cdid => $_->[3] },
            { tracks => [
              { title => $_->[2] }
            ] },
          ] },
        ] },
      ] },
    ] },
  ] for @{$_[0]}',
  '1:1 descending non-collapsing parser terminating with chained 1:M:M',
);

is_deeply (
  $schema->source('CD')->_resolve_collapse({map { $infmap->[$_] => $_ } 0 .. $#$infmap}),
  {
    -node_index => 1,
    -node_id => [ 4, 5 ],
    -branch_id => [ 0, 2, 3, 4, 5 ],

    single_track => {
      -node_index => 2,
      -node_id => [ 4, 5],
      -branch_id => [ 0, 2, 3, 4, 5],
      -is_optional => 1,
      -is_single => 1,

      cd => {
        -node_index => 3,
        -node_id => [ 4, 5 ],
        -branch_id => [ 0, 2, 3, 4, 5 ],
        -is_single => 1,

        artist => {
          -node_index => 4,
          -node_id => [ 0 ],
          -branch_id => [ 0, 2, 3 ],
          -is_single => 1,

          cds => {
            -node_index => 5,
            -node_id => [ 3 ],
            -branch_id => [ 2, 3 ],
            -is_optional => 1,

            tracks => {
              -node_index => 6,
              -node_id => [ 2, 3 ],
              -branch_id => [ 2, 3 ],
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
  $schema->source ('CD')->_mk_row_parser({
    inflate_map => $infmap,
    collapse => 1,
  }),
  ' my($rows_pos, $result_pos, $cur_row, @cur_row_ids, @collapse_idx, $is_new_res) = (0, 0);

    while ($cur_row = (
      ( $rows_pos >= 0 and $_[0][$rows_pos++] ) or do { $rows_pos = -1; undef } )
        ||
      ( $_[1] and $_[1]->() )
    ) {

      $cur_row_ids[$_] = defined $cur_row->[$_] ? $cur_row->[$_] : "\xFF\xFFN\xFFU\xFFL\xFFL\xFF\xFF"
        for (0, 2, 3, 4, 5);

      # a present cref implies lazy prefetch, implies a supplied stash in $_[2]
      $_[1] and $result_pos and unshift(@{$_[2]}, $cur_row) and last
        if $is_new_res = ! $collapse_idx[1]{$cur_row_ids[4]}{$cur_row_ids[5]};

      $collapse_idx[1]{$cur_row_ids[4]}{$cur_row_ids[5]} ||= [{ artist => $cur_row->[5], title => $cur_row->[4], year => $cur_row->[1] }];
      $collapse_idx[1]{$cur_row_ids[4]}{$cur_row_ids[5]}[1]{single_track} ||= $collapse_idx[2]{$cur_row_ids[4]}{$cur_row_ids[5]};
      $collapse_idx[2]{$cur_row_ids[4]}{$cur_row_ids[5]}[1]{cd} ||= $collapse_idx[3]{$cur_row_ids[4]}{$cur_row_ids[5]};
      $collapse_idx[3]{$cur_row_ids[4]}{$cur_row_ids[5]}[1]{artist} ||= $collapse_idx[4]{$cur_row_ids[0]} ||= [{ artistid => $cur_row->[0] }];

      $collapse_idx[4]{$cur_row_ids[0]}[1]{cds} ||= [];
      push @{$collapse_idx[4]{$cur_row_ids[0]}[1]{cds}}, $collapse_idx[5]{$cur_row_ids[3]} ||= [{ cdid => $cur_row->[3] }]
        unless $collapse_idx[5]{$cur_row_ids[3]};

      $collapse_idx[5]{$cur_row_ids[3]}[1]{tracks} ||= [];
      push @{$collapse_idx[5]{$cur_row_ids[3]}[1]{tracks}}, $collapse_idx[6]{$cur_row_ids[2]}{$cur_row_ids[3]} ||= [{ title => $cur_row->[2] }]
        unless $collapse_idx[6]{$cur_row_ids[2]}{$cur_row_ids[3]};

      $_[0][$result_pos++] = $collapse_idx[1]{$cur_row_ids[4]}{$cur_row_ids[5]}
        if $is_new_res;
    }
    splice @{$_[0]}, $result_pos;
  ',
  'Same 1:1 descending terminating with chained 1:M:M but with collapse',
);

$infmap = [qw/
  tracks.lyrics.lyric_versions.text
  existing_single_track.cd.artist.artistid
  existing_single_track.cd.artist.cds.year
  year
  genreid
  tracks.title
  existing_single_track.cd.artist.cds.cdid
  latest_cd
  existing_single_track.cd.artist.cds.tracks.title
  existing_single_track.cd.artist.cds.genreid
/];

is_deeply (
  $schema->source('CD')->_resolve_collapse({map { $infmap->[$_] => $_ } 0 .. $#$infmap}),
  {
    -node_index => 1,
    -node_id => [ 1 ], # existing_single_track.cd.artist.artistid
    -branch_id => [ 0, 1, 5, 6, 8 ],

    existing_single_track => {
      -node_index => 2,
      -node_id => [ 1 ], # existing_single_track.cd.artist.artistid
      -branch_id => [ 1, 6, 8 ],
      -is_single => 1,

      cd => {
        -node_index => 3,
        -node_id => [ 1 ], # existing_single_track.cd.artist.artistid
        -branch_id => [ 1, 6, 8 ],
        -is_single => 1,

        artist => {
          -node_index => 4,
          -node_id => [ 1 ], # existing_single_track.cd.artist.artistid
          -branch_id => [ 1, 6, 8 ],
          -is_single => 1,

          cds => {
            -node_index => 5,
            -node_id => [ 6 ], # existing_single_track.cd.artist.cds.cdid
            -branch_id => [ 6, 8 ],
            -is_optional => 1,

            tracks => {
              -node_index => 6,
              -node_id => [ 6, 8 ], # existing_single_track.cd.artist.cds.cdid, existing_single_track.cd.artist.cds.tracks.title
              -branch_id => [ 6, 8 ],
              -is_optional => 1,
            }
          }
        }
      }
    },
    tracks => {
      -node_index => 7,
      -node_id => [ 1, 5 ], # existing_single_track.cd.artist.artistid, tracks.title
      -branch_id => [ 0, 1, 5 ],
      -is_optional => 1,

      lyrics => {
        -node_index => 8,
        -node_id => [ 1, 5 ], # existing_single_track.cd.artist.artistid, tracks.title
        -branch_id => [ 0, 1, 5 ],
        -is_single => 1,
        -is_optional => 1,

        lyric_versions => {
          -node_index => 9,
          -node_id => [ 0, 1, 5 ], # tracks.lyrics.lyric_versions.text, existing_single_track.cd.artist.artistid, tracks.title
          -branch_id => [ 0, 1, 5 ],
          -is_optional => 1,
        },
      },
    }
  },
  'Correct collapse map constructed',
);

is_same_src (
  $schema->source ('CD')->_mk_row_parser({
    inflate_map => $infmap,
    collapse => 1,
  }),
  ' my ($rows_pos, $result_pos, $cur_row, @cur_row_ids, @collapse_idx, $is_new_res) = (0,0);

    while ($cur_row = (
      ( $rows_pos >= 0 and $_[0][$rows_pos++] ) or do { $rows_pos = -1; undef } )
        ||
      ( $_[1] and $_[1]->() )
    ) {

      $cur_row_ids[$_] = defined $cur_row->[$_] ? $cur_row->[$_] : "\xFF\xFFN\xFFU\xFFL\xFFL\xFF\xFF"
        for (0, 1, 5, 6, 8);

      $is_new_res = ! $collapse_idx[1]{$cur_row_ids[1]} and (
        $_[1] and $result_pos and (unshift @{$_[2]}, $cur_row) and last
      );

      $collapse_idx[1]{$cur_row_ids[1]} ||= [{ latest_cd => $cur_row->[7], year => $cur_row->[3], genreid => $cur_row->[4] }];

      $collapse_idx[1]{$cur_row_ids[1]}[1]{existing_single_track} ||= $collapse_idx[2]{$cur_row_ids[1]};
      $collapse_idx[2]{$cur_row_ids[1]}[1]{cd} ||= $collapse_idx[3]{$cur_row_ids[1]};
      $collapse_idx[3]{$cur_row_ids[1]}[1]{artist} ||= $collapse_idx[4]{$cur_row_ids[1]} ||= [{ artistid => $cur_row->[1] }];

      $collapse_idx[4]{$cur_row_ids[1]}[1]{cds} ||= [];
      push @{ $collapse_idx[4]{$cur_row_ids[1]}[1]{cds} }, $collapse_idx[5]{$cur_row_ids[6]} ||= [{ cdid => $cur_row->[6], genreid => $cur_row->[9], year => $cur_row->[2] }]
        unless $collapse_idx[5]{$cur_row_ids[6]};

      $collapse_idx[5]{$cur_row_ids[6]}[1]{tracks} ||= [];
      push @{ $collapse_idx[5]{$cur_row_ids[6]}[1]{tracks} }, $collapse_idx[6]{$cur_row_ids[6]}{$cur_row_ids[8]} ||= [{ title => $cur_row->[8] }]
        unless $collapse_idx[6]{$cur_row_ids[6]}{$cur_row_ids[8]};

      $collapse_idx[1]{$cur_row_ids[1]}[1]{tracks} ||= [];
      push @{ $collapse_idx[1]{$cur_row_ids[1]}[1]{tracks} }, $collapse_idx[7]{$cur_row_ids[1]}{$cur_row_ids[5]} ||= [{ title => $cur_row->[5] }]
        unless $collapse_idx[7]{$cur_row_ids[1]}{$cur_row_ids[5]};

      $collapse_idx[7]{$cur_row_ids[1]}{$cur_row_ids[5]}[1]{lyrics} ||= $collapse_idx[8]{$cur_row_ids[1]}{$cur_row_ids[5] };

      $collapse_idx[8]{$cur_row_ids[1]}{$cur_row_ids[5]}[1]{lyric_versions} ||= [];
      push @{ $collapse_idx[8]{$cur_row_ids[1]}{$cur_row_ids[5]}[1]{lyric_versions} }, $collapse_idx[9]{$cur_row_ids[0]}{$cur_row_ids[1]}{$cur_row_ids[5]} ||= [{ text => $cur_row->[0] }]
        unless $collapse_idx[9]{$cur_row_ids[0]}{$cur_row_ids[1]}{$cur_row_ids[5]};

      $_[0][$result_pos++] = $collapse_idx[1]{$cur_row_ids[1]}
        if $is_new_res;
    }

    splice @{$_[0]}, $result_pos;
  ',
  'Multiple has_many on multiple branches torture test',
);

done_testing;

my $deparser;
sub is_same_src {
  $deparser ||= B::Deparse->new;
  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my ($got, $expect) = map {
    my $cref = eval "sub { $_ }" or do {
      fail "Coderef does not compile!\n\n$@\n\n$_";
      return undef;
    };
    $deparser->coderef2text($cref);
  } @_[0,1];

  is ($got, $expect, $_[2]||() )
    or note ("Originals source:\n\n$_[0]\n\n$_[1]\n");
}

