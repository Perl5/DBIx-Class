use strict;
use warnings;
no warnings 'exiting';

use Test::More;
use Test::Deep;
use lib qw(t/lib);
use Test::Exception;

use DBICTest;

my $schema = DBICTest->init_schema(no_populate => 1);

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

$schema->resultset('CD')->create({ artist => 1, year => 1977, title => "fuzzy_1" });

$schema->resultset('Artist')->create({ name => "${_}_cdless" })
  for (qw( Z A ));

# subs at the end of the test refer to this
my $native_inflator;

### TESTS START
# run entire test twice - with and without "native inflator"
INFTYPE: for ('', '(native inflator)') {

  $native_inflator = $_;

  cmp_structures(
    rs_contents( $schema->resultset ('CD')->search_rs ({}, {
      prefetch => { single_track => { cd => 'artist' } },
      order_by => 'me.cdid',
    }) ),
    [
      [
        { cdid => 1, single_track => undef, artist => 1, genreid => 1, year => 1981, title => "Magnetic Fields" },
        { single_track => code(sub { null_branch ( \@_, [
          { trackid => undef, title => undef, position => undef, cd => undef, last_updated_at => undef, last_updated_on => undef },
          {  cd => code(sub { null_branch ( \@_, [
            { cdid => undef, single_track => undef, artist => undef, genreid => undef, year => undef, title => undef },
            {
              artist => code(sub { null_branch ( \@_, [
                { artistid => undef, name => undef, charfield => undef, rank => undef }
              ] ) } )
            }
          ] ) } ) }
        ] ) } ) }
      ],
      [
        { cdid => 2, single_track => undef, artist => 1, genreid => undef, year => 1976, title => "Oxygene" },
        { single_track => code(sub { null_branch ( \@_, [
          { trackid => undef, title => undef, position => undef, cd => undef, last_updated_at => undef, last_updated_on => undef },
          {  cd => code(sub { null_branch ( \@_, [
            { cdid => undef, single_track => undef, artist => undef, genreid => undef, year => undef, title => undef },
            {
              artist => code(sub { null_branch ( \@_, [
                { artistid => undef, name => undef, charfield => undef, rank => undef }
              ] ) } )
            }
          ] ) } ) }
        ] ) } ) }
      ],
      [
        { cdid => 3, single_track => 6, artist => 1, genreid => 1, year => 1978, title => "Equinoxe" },
        { single_track => [
          { trackid => 6, title => 'o1', position => 1, cd => 2, last_updated_at => undef, last_updated_on => undef },
          {  cd => [
            { cdid => 2, single_track => undef, artist => 1, genreid => undef, year => 1976, title => "Oxygene" },
            {
              artist => [
                { artistid => 1, name => 'JMJ', charfield => undef, rank => 13 }
              ]
            }
          ] }
        ] }
      ],
      [
        { cdid => 4, single_track => undef, artist => 1, genreid => undef, year => 1977, title => "fuzzy_1" },
        { single_track => code(sub { null_branch ( \@_, [
          { trackid => undef, title => undef, position => undef, cd => undef, last_updated_at => undef, last_updated_on => undef },
          {  cd => code(sub { null_branch ( \@_, [
            { cdid => undef, single_track => undef, artist => undef, genreid => undef, year => undef, title => undef },
            {
              artist => code(sub { null_branch ( \@_, [
                { artistid => undef, name => undef, charfield => undef, rank => undef }
              ] ) } )
            }
          ] ) } ) }
        ] ) } ) }
      ],
    ],
    "Simple 1:1 descend with classic prefetch $native_inflator"
  );

  cmp_structures(
    rs_contents( $schema->resultset ('CD')->search_rs ({}, {
      join => { single_track => { cd => 'artist' } },
      columns => [
        { 'year'                                    => 'me.year' },
        { 'genreid'                                 => 'me.genreid' },
        { 'single_track.cd.artist.artistid'         => 'artist.artistid' },
        { 'title'                                   => 'me.title' },
        { 'artist'                                  => 'me.artist' },
      ],
      order_by => 'me.cdid',
    }) ),
    [
      [
        { artist => 1, genreid => 1, year => 1981, title => "Magnetic Fields" },
        { single_track => code(sub { null_branch ( \@_, [
          undef,
          {  cd => [
            undef,
            {
              artist => [
                { artistid => undef }
              ]
            }
          ] }
        ] ) } ) }
      ],
      [
        { artist => 1, genreid => undef, year => 1976, title => "Oxygene" },
        { single_track => code(sub { null_branch ( \@_, [
          undef,
          {  cd => [
            undef,
            {
              artist => [
                { artistid => undef }
              ]
            }
          ] }
        ] ) } ) }
      ],
      [
        { artist => 1, genreid => 1, year => 1978, title => "Equinoxe" },
        { single_track => [
          undef,
          {  cd => [
            undef,
            {
              artist => [
                { artistid => 1 }
              ]
            }
          ] }
        ] }
      ],
      [
        { artist => 1, genreid => undef, year => 1977, title => "fuzzy_1" },
        { single_track => code(sub { null_branch ( \@_, [
          undef,
          {  cd => [
            undef,
            {
              artist => [
                { artistid => undef }
              ]
            }
          ] }
        ] ) } ) }
      ],
    ],
    "Simple 1:1 descend with missing selectors $native_inflator",
  );

  cmp_structures(
    rs_contents( $schema->resultset ('CD')->search_rs ({}, {
      prefetch => [ { single_track => { cd => { artist => { cds => 'tracks' } } } } ],
      order_by => [qw/me.cdid tracks.trackid/],
    }) ),
    [
      [
        { cdid => 1, single_track => undef, artist => 1, genreid => 1, year => 1981, title => "Magnetic Fields" },
        { single_track => code(sub { null_collapsed_branch ( \@_, [
          { trackid => undef, title => undef, position => undef, cd => undef, last_updated_at => undef, last_updated_on => undef },
          {  cd => [
            { cdid => undef, single_track => undef, artist => undef, genreid => undef, year => undef, title => undef },
            {
              artist => [
                { artistid => undef, name => undef, charfield => undef, rank => undef },
                { cds => code(sub { null_collapsed_branch ( \@_, [ [
                  { cdid => undef, single_track => undef, artist => undef, genreid => undef, year => undef, title => undef },
                  { tracks => code(sub { null_collapsed_branch ( \@_, [ [
                    { trackid => undef, title => undef, position => undef, cd => undef, last_updated_at => undef, last_updated_on => undef },
                  ] ] ) } ) },
                ] ] ) } ) },
              ],
            },
          ] },
        ] ) } ) },
      ],
      [
        { cdid => 2, single_track => undef, artist => 1, genreid => undef, year => 1976, title => "Oxygene" },
        { single_track => code(sub { null_collapsed_branch ( \@_, [
          { trackid => undef, title => undef, position => undef, cd => undef, last_updated_at => undef, last_updated_on => undef },
          {  cd => [
            { cdid => undef, single_track => undef, artist => undef, genreid => undef, year => undef, title => undef },
            {
              artist => [
                { artistid => undef, name => undef, charfield => undef, rank => undef },
                { cds => code(sub { null_collapsed_branch ( \@_, [ [
                  { cdid => undef, single_track => undef, artist => undef, genreid => undef, year => undef, title => undef },
                  { tracks => code(sub { null_collapsed_branch ( \@_, [ [
                    { trackid => undef, title => undef, position => undef, cd => undef, last_updated_at => undef, last_updated_on => undef },
                  ] ] ) } ) },
                ] ] ) } ) },
              ],
            },
          ] },
        ] ) } ) },
      ],
      [
        { cdid => 3, single_track => 6, artist => 1, genreid => 1, year => 1978, title => "Equinoxe" },
        { single_track => [
          { trackid => 6, title => 'o1', position => 1, cd => 2, last_updated_at => undef, last_updated_on => undef },
          {  cd => [
            { cdid => 2, single_track => undef, artist => 1, genreid => undef, year => 1976, title => "Oxygene" },
            {
              artist => [
                { artistid => 1, name => 'JMJ', charfield => undef, rank => 13 },
                { cds => [
                  [
                    { cdid => 4, single_track => undef, artist => 1, genreid => undef, year => 1977, title => "fuzzy_1" },
                    { tracks => code(sub { null_collapsed_branch ( \@_, [
                      [ { trackid => undef, title => undef, position => undef, cd => undef, last_updated_at => undef, last_updated_on => undef } ],
                    ] ) } ) },
                  ],
                  [
                    { cdid => 1, single_track => undef, artist => 1, genreid => 1, year => 1981, title => "Magnetic Fields" },
                    { tracks => [
                      [ { trackid => 1, title => 'm1', position => 1, cd => 1, last_updated_at => undef, last_updated_on => undef } ],
                      [ { trackid => 2, title => 'm2', position => 2, cd => 1, last_updated_at => undef, last_updated_on => undef } ],
                      [ { trackid => 3, title => 'm3', position => 3, cd => 1, last_updated_at => undef, last_updated_on => undef } ],
                      [ { trackid => 4, title => 'm4', position => 4, cd => 1, last_updated_at => undef, last_updated_on => undef } ],
                    ]},
                  ],
                  [
                    { cdid => 2, single_track => undef, artist => 1, genreid => undef, year => 1976, title => "Oxygene" },
                    { tracks => [
                      [ { trackid => 5, title => 'o2', position => 2, cd => 2, last_updated_at => undef, last_updated_on => undef } ],
                      [ { trackid => 6, title => 'o1', position => 1, cd => 2, last_updated_at => undef, last_updated_on => undef } ],
                    ]},
                  ],
                  [
                    { cdid => 3, single_track => 6, artist => 1, genreid => 1, year => 1978, title => "Equinoxe" },
                    { tracks => [
                      [ { trackid => 7, title => 'e1', position => 1, cd => 3, last_updated_at => undef, last_updated_on => undef } ],
                      [ { trackid => 8, title => 'e2', position => 2, cd => 3, last_updated_at => undef, last_updated_on => undef } ],
                      [ { trackid => 9, title => 'e3', position => 3, cd => 3, last_updated_at => undef, last_updated_on => undef } ],
                    ]},
                  ],
                ]},
              ]
            }
          ] }
        ] }
      ],
      [
        { cdid => 4, single_track => undef, artist => 1, genreid => undef, year => 1977, title => "fuzzy_1" },
        { single_track => code(sub { null_collapsed_branch ( \@_, [
          { trackid => undef, title => undef, position => undef, cd => undef, last_updated_at => undef, last_updated_on => undef },
          {  cd => [
            { cdid => undef, single_track => undef, artist => undef, genreid => undef, year => undef, title => undef },
            {
              artist => [
                { artistid => undef, name => undef, charfield => undef, rank => undef },
                { cds => code(sub { null_collapsed_branch ( \@_, [ [
                  { cdid => undef, single_track => undef, artist => undef, genreid => undef, year => undef, title => undef },
                  { tracks => code(sub { null_collapsed_branch ( \@_, [ [
                    { trackid => undef, title => undef, position => undef, cd => undef, last_updated_at => undef, last_updated_on => undef },
                  ] ] ) } ) },
                ] ] ) } ) },
              ],
            },
          ] },
        ] ) } ) },
      ],
    ],
    "Collapsing 1:1 ending in chained has_many with classic prefetch $native_inflator",
  );

  cmp_structures (
    rs_contents( $schema->resultset ('Artist')->search_rs ({}, {
      join => { cds => 'tracks' },
      '+columns' => [
        (map { "cds.$_" } $schema->source('CD')->columns),
        (map { +{ "cds.tracks.$_" => "tracks.$_" } } $schema->source('Track')->columns),
      ],
      order_by => [qw/cds.cdid tracks.trackid me.name/],
    }) ),
    [
      [
        { artistid => 3, name => 'A_cdless', charfield => undef, rank => 13 },
        { cds => code(sub { null_branch ( \@_, [
          { cdid => undef, single_track => undef, artist => undef, genreid => undef, year => undef, title => undef },
          { tracks => code(sub { null_branch ( \@_, [
            { trackid => undef, title => undef, position => undef, cd => undef, last_updated_at => undef, last_updated_on => undef },
          ] ) } ) },
        ] ) } ) },
      ],
      [
        { artistid => 2, name => 'Z_cdless', charfield => undef, rank => 13 },
        { cds => code(sub { null_branch ( \@_, [
          { cdid => undef, single_track => undef, artist => undef, genreid => undef, year => undef, title => undef },
          { tracks => code(sub { null_branch ( \@_, [
            { trackid => undef, title => undef, position => undef, cd => undef, last_updated_at => undef, last_updated_on => undef },
          ] ) } ) },
        ] ) } ) },
      ],
      [
        { artistid => 1, name => 'JMJ', charfield => undef, rank => 13 },
        { cds => [
          { cdid => 1, single_track => undef, artist => 1, genreid => 1, year => 1981, title => "Magnetic Fields" },
          { tracks => [
            { trackid => 1, title => 'm1', position => 1, cd => 1, last_updated_at => undef, last_updated_on => undef },
          ]},
        ]},
      ],
      [
        { artistid => 1, name => 'JMJ', charfield => undef, rank => 13 },
        { cds => [
          { cdid => 1, single_track => undef, artist => 1, genreid => 1, year => 1981, title => "Magnetic Fields" },
          { tracks => [
            { trackid => 2, title => 'm2', position => 2, cd => 1, last_updated_at => undef, last_updated_on => undef },
          ]},
        ]},
      ],
      [
        { artistid => 1, name => 'JMJ', charfield => undef, rank => 13 },
        { cds => [
          { cdid => 1, single_track => undef, artist => 1, genreid => 1, year => 1981, title => "Magnetic Fields" },
          { tracks => [
            { trackid => 3, title => 'm3', position => 3, cd => 1, last_updated_at => undef, last_updated_on => undef },
          ]},
        ]},
      ],
      [
        { artistid => 1, name => 'JMJ', charfield => undef, rank => 13 },
        { cds => [
          { cdid => 1, single_track => undef, artist => 1, genreid => 1, year => 1981, title => "Magnetic Fields" },
          { tracks => [
            { trackid => 4, title => 'm4', position => 4, cd => 1, last_updated_at => undef, last_updated_on => undef },
          ]},
        ]},
      ],
      [
        { artistid => 1, name => 'JMJ', charfield => undef, rank => 13 },
        { cds => [
          { cdid => 2, single_track => undef, artist => 1, genreid => undef, year => 1976, title => "Oxygene" },
          { tracks => [
            { trackid => 5, title => 'o2', position => 2, cd => 2, last_updated_at => undef, last_updated_on => undef },
          ]},
        ]},
      ],
      [
        { artistid => 1, name => 'JMJ', charfield => undef, rank => 13 },
        { cds => [
          { cdid => 2, single_track => undef, artist => 1, genreid => undef, year => 1976, title => "Oxygene" },
          { tracks => [
            { trackid => 6, title => 'o1', position => 1, cd => 2, last_updated_at => undef, last_updated_on => undef },
          ]},
        ]},
      ],
      [
        { artistid => 1, name => 'JMJ', charfield => undef, rank => 13 },
        { cds => [
          { cdid => 3, single_track => 6, artist => 1, genreid => 1, year => 1978, title => "Equinoxe" },
          { tracks => [
            { trackid => 7, title => 'e1', position => 1, cd => 3, last_updated_at => undef, last_updated_on => undef },
          ]},
        ]},
      ],
      [
        { artistid => 1, name => 'JMJ', charfield => undef, rank => 13 },
        { cds => [
          { cdid => 3, single_track => 6, artist => 1, genreid => 1, year => 1978, title => "Equinoxe" },
          { tracks => [
            { trackid => 8, title => 'e2', position => 2, cd => 3, last_updated_at => undef, last_updated_on => undef },
          ]},
        ]},
      ],
      [
        { artistid => 1, name => 'JMJ', charfield => undef, rank => 13 },
        { cds => [
          { cdid => 3, single_track => 6, artist => 1, genreid => 1, year => 1978, title => "Equinoxe" },
          { tracks => [
            { trackid => 9, title => 'e3', position => 3, cd => 3, last_updated_at => undef, last_updated_on => undef },
          ]},
        ]},
      ],
      [
        { artistid => 1, name => 'JMJ', charfield => undef, rank => 13 },
        { cds => [
          { cdid => 4, single_track => undef, artist => 1, genreid => undef, year => 1977, title => "fuzzy_1" },
          { tracks => code(sub { null_branch ( \@_, [
            { trackid => undef, title => undef, position => undef, cd => undef, last_updated_at => undef, last_updated_on => undef },
          ] ) } ) },
        ]},
      ],
    ],
    "Non-Collapsing chained has_many $native_inflator",
  );

  cmp_structures (
    rs_contents( $schema->resultset ('Artist')->search_rs ({}, {
      collapse => 1,
      join => 'cds',
      columns => [qw( cds.title cds.artist )],
      order_by => [qw( me.name cds.title )],
    }) ),
    [
      [
        undef,
        { cds => code(sub { null_collapsed_branch ( \@_, [
          [ { artist => undef, title => undef } ]
        ] ) } ) },
      ],
      [
        undef,
        { cds => [
          [ { artist => 1, title => "Equinoxe" } ],
          [ { artist => 1, title => "Magnetic Fields" } ],
          [ { artist => 1, title => "Oxygene" } ],
          [ { artist => 1, title => "fuzzy_1" } ],
        ] }
      ],
      [
        undef,
        { cds => code(sub { null_collapsed_branch ( \@_, [
          [ { artist => undef, title => undef } ]
        ] ) } ) },
      ],
    ],
    "Expected output of collapsing 1:M with empty root selection $native_inflator",
  );
}

sub null_branch {
  cmp_deeply(
    $_[0][0],
    $native_inflator ? undef : bless( $_[1], $DBIx::Class::ResultSource::RowParser::Util::null_branch_class ),
  );
}
sub null_collapsed_branch {
  cmp_deeply(
    $_[0][0],
    $native_inflator ? [] : bless( $_[1], $DBIx::Class::ResultSource::RowParser::Util::null_branch_class ),
  );
}

{
  package DBICTest::_IRCapture;
  sub inflate_result { [@_[2,3]] };
}

sub rs_contents {
  my $rs = shift;
  $rs->result_class('DBICTest::_IRCapture');
  die 'eeeeek - preprocessed $rs' if defined $rs->{_result_inflator}{is_core_row};
  $rs->{_result_inflator}{is_core_row} = 1 if $native_inflator;
  [$rs->all],
}

sub cmp_structures {
  my ($left, $right, $msg) = @_;

  local $Test::Builder::Level = $Test::Builder::Level + 1;
  cmp_deeply($left, $right, $msg||()) or next INFTYPE;
}


{
  package DBICTest::_DoubleResult;

  sub inflate_result {
    my $class = shift;
    return map { DBIx::Class::ResultClass::HashRefInflator->inflate_result(@_) } (1,2);
  }
}

my $oxygene_rs = $schema->resultset('CD')->search({ 'me.title' => 'Oxygene' });

is_deeply(
  [ $oxygene_rs->search({}, { result_class => 'DBICTest::_DoubleResult' })->all ],
  [ ({ $oxygene_rs->single->get_columns }) x 2 ],
);

is_deeply(
  [ $oxygene_rs->search({}, {
    result_class => 'DBICTest::_DoubleResult', prefetch => [qw(artist tracks)],
    order_by => [qw(me.cdid tracks.title)],
  })->all ],
  [ (@{$oxygene_rs->search({}, {
    prefetch=> [qw(artist tracks)],
    order_by => [qw(me.cdid tracks.title)],
  })->all_hri}) x 2 ],
);


{
  package DBICTest::_DieTrying;

  sub inflate_result {
    die "nyah nyah nyah";
  }
}

throws_ok {
  $schema->resultset('CD')->search({}, { result_class => 'DBICTest::_DieTrying' })->all
} qr/nyah nyah nyah/, 'Exception in custom inflate_result propagated correctly';


done_testing;
