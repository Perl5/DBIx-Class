use strict;
use warnings;

use Test::More;
use Test::Exception;
use Test::Warn;
use lib qw(t/lib);
use DBICTest;
use DBIx::Class::_Util 'sigwarn_silencer';
use Path::Class::File ();
use Math::BigInt;
use List::Util qw/shuffle/;
use Storable qw/nfreeze dclone/;

my $schema = DBICTest->init_schema();

# The map below generates stuff like:
#   [ qw/artistid name/ ],
#   [ 4, "b" ],
#   [ 5, "c" ],
#   ...
#   [ 9999, "ntm" ],
#   [ 10000, "ntn" ],

my $start_id = 'populateXaaaaaa';
my $rows = 10_000;
my $offset = 3;

$schema->populate('Artist', [ [ qw/artistid name/ ], map { [ ($_ + $offset) => $start_id++ ] } shuffle ( 1 .. $rows ) ] );
is (
    $schema->resultset ('Artist')->search ({ name => { -like => 'populateX%' } })->count,
    $rows,
    'populate created correct number of rows with massive AoA bulk insert',
);

my $artist = $schema->resultset ('Artist')
              ->search ({ 'cds.title' => { '!=', undef } }, { join => 'cds' })
                ->first;
my $ex_title = $artist->cds->first->title;

throws_ok ( sub {
  my $i = 600;
  $schema->populate('CD', [
    map {
      {
        artist => $artist->id,
        title => $_,
        year => 2009,
      }
    } ('Huey', 'Dewey', $ex_title, 'Louie')
  ])
}, qr/\Qexecute_for_fetch() aborted with '\E.+ at populate slice.+$ex_title/ms, 'Readable exception thrown for failed populate');

## make sure populate honors fields/orders in list context
## schema order
my @links = $schema->populate('Link', [
[ qw/id url title/ ],
[ qw/2 burl btitle/ ]
]);
is(scalar @links, 1);

my $link2 = shift @links;
is($link2->id, 2, 'Link 2 id');
is($link2->url, 'burl', 'Link 2 url');
is($link2->title, 'btitle', 'Link 2 title');

## non-schema order
@links = $schema->populate('Link', [
[ qw/id title url/ ],
[ qw/3 ctitle curl/ ]
]);
is(scalar @links, 1);

my $link3 = shift @links;
is($link3->id, 3, 'Link 3 id');
is($link3->url, 'curl', 'Link 3 url');
is($link3->title, 'ctitle', 'Link 3 title');

## not all physical columns
@links = $schema->populate('Link', [
[ qw/id title/ ],
[ qw/4 dtitle/ ]
]);
is(scalar @links, 1);

my $link4 = shift @links;
is($link4->id, 4, 'Link 4 id');
is($link4->url, undef, 'Link 4 url');
is($link4->title, 'dtitle', 'Link 4 title');

## variable size dataset
@links = $schema->populate('Link', [
[ qw/id title url/ ],
[ 41 ],
[ 42, undef, 'url42' ],
]);
is(scalar @links, 2);
is($links[0]->url, undef);
is($links[1]->url, 'url42');

## make sure populate -> _insert_bulk honors fields/orders in void context
## schema order
$schema->populate('Link', [
[ qw/id url title/ ],
[ qw/5 eurl etitle/ ]
]);
my $link5 = $schema->resultset('Link')->find(5);
is($link5->id, 5, 'Link 5 id');
is($link5->url, 'eurl', 'Link 5 url');
is($link5->title, 'etitle', 'Link 5 title');

## non-schema order
$schema->populate('Link', [
[ qw/id title url/ ],
[ qw/6 ftitle furl/ ]
]);
my $link6 = $schema->resultset('Link')->find(6);
is($link6->id, 6, 'Link 6 id');
is($link6->url, 'furl', 'Link 6 url');
is($link6->title, 'ftitle', 'Link 6 title');

## not all physical columns
$schema->populate('Link', [
[ qw/id title/ ],
[ qw/7 gtitle/ ]
]);
my $link7 = $schema->resultset('Link')->find(7);
is($link7->id, 7, 'Link 7 id');
is($link7->url, undef, 'Link 7 url');
is($link7->title, 'gtitle', 'Link 7 title');

## variable size dataset in void ctx
$schema->populate('Link', [
[ qw/id title url/ ],
[ 71 ],
[ 72, undef, 'url72' ],
]);
@links = $schema->resultset('Link')->search({ id => [71, 72]}, { order_by => 'id' })->all;
is(scalar @links, 2);
is($links[0]->url, undef);
is($links[1]->url, 'url72');

## variable size dataset in void ctx, hash version
$schema->populate('Link', [
  { id => 73 },
  { id => 74, title => 't74' },
  { id => 75, url => 'u75' },
]);
@links = $schema->resultset('Link')->search({ id => [73..75]}, { order_by => 'id' })->all;
is(scalar @links, 3);
is($links[0]->url, undef);
is($links[0]->title, undef);
is($links[1]->url, undef);
is($links[1]->title, 't74');
is($links[2]->url, 'u75');
is($links[2]->title, undef);

## Make sure the void ctx trace is sane
{
  for (
    [
      [ qw/id title url/ ],
      [ 81 ],
      [ 82, 't82' ],
      [ 83, undef, 'url83' ],
    ],
    [
      { id => 91 },
      { id => 92, title => 't92' },
      { id => 93, url => 'url93' },
    ]
  ) {
    $schema->is_executed_sql_bind(
      sub {
        $schema->populate('Link', $_);
      },
      [
        [ 'BEGIN' ],
        [
          'INSERT INTO link( id, title, url ) VALUES( ?, ?, ? )',
          "__BULK_INSERT__"
        ],
        [ 'COMMIT' ],
      ]
    );
  }
}

# populate with literals
{
  my $rs = $schema->resultset('Link');
  $rs->delete;

  # test populate with all literal sql (no binds)

  $rs->populate([
    (+{
        url => \"'cpan.org'",
        title => \"'The ''best of'' cpan'",
    }) x 5
  ]);

  is((grep {
    $_->url eq 'cpan.org' &&
    $_->title eq "The 'best of' cpan",
  } $rs->all), 5, 'populate with all literal SQL');

  $rs->delete;

  # test mixed binds with literal sql

  $rs->populate([
    (+{
        url => \"'cpan.org'",
        title => "The 'best of' cpan",
    }) x 5
  ]);

  is((grep {
    $_->url eq 'cpan.org' &&
    $_->title eq "The 'best of' cpan",
  } $rs->all), 5, 'populate with all literal SQL');

  $rs->delete;
}

# populate with literal+bind
{
  my $rs = $schema->resultset('Link');
  $rs->delete;

  # test populate with all literal/bind sql
  $rs->populate([
    (+{
        url => \['?', [ {} => 'cpan.org' ] ],
        title => \['?', [ {} => "The 'best of' cpan" ] ],
    }) x 5
  ]);

  is((grep {
    $_->url eq 'cpan.org' &&
    $_->title eq "The 'best of' cpan",
  } $rs->all), 5, 'populate with all literal/bind');

  $rs->delete;

  # test populate with mix literal and literal/bind
  $rs->populate([
    (+{
        url => \"'cpan.org'",
        title => \['?', [ {} => "The 'best of' cpan" ] ],
    }) x 5
  ]);

  is((grep {
    $_->url eq 'cpan.org' &&
    $_->title eq "The 'best of' cpan",
  } $rs->all), 5, 'populate with all literal/bind SQL');

  $rs->delete;

  # test mixed binds with literal sql/bind

  $rs->populate([ map { +{
    url => \[ '? || ?', [ {} => 'cpan.org_' ], $_ ],
    title => "The 'best of' cpan",
  } } (1 .. 5) ]);

  for (1 .. 5) {
    ok($rs->find({ url => "cpan.org_$_" }), "Row $_ correctly created with dynamic literal/bind populate" );
  }

  $rs->delete;
}

my $rs = $schema->resultset('Artist');
$rs->delete;
throws_ok {
    # this warning is correct, but we are not testing it here
    # what we are after is the correct exception when an int
    # fails to coerce into a sqlite rownum
    local $SIG{__WARN__} = sigwarn_silencer( qr/datatype mismatch.+ foo as integer/ );

    $rs->populate([
        {
            artistid => 1,
            name => 'foo1',
        },
        {
            artistid => 'foo', # this dies
            name => 'foo2',
        },
        {
            artistid => 3,
            name => 'foo3',
        },
    ]);
} qr/\Qexecute_for_fetch() aborted with 'datatype mismatch\E\b/, 'bad slice fails PK insert';

is($rs->count, 0, 'populate is atomic');

# Trying to use a column marked as a bind in the first slice with literal sql in
# a later slice should throw.

throws_ok {
  $rs->populate([
    {
      artistid => 1,
      name => \"'foo'",
    },
    {
      artistid => \2,
      name => \"'foo'",
    }
  ]);
} qr/Literal SQL found where a plain bind value is expected/, 'literal sql where bind expected throws';

# ... and vice-versa.

throws_ok {
  $rs->populate([
    {
      artistid => \1,
      name => \"'foo'",
    },
    {
      artistid => 2,
      name => \"'foo'",
    }
  ]);
} qr/\QIncorrect value (expecting SCALAR-ref/, 'bind where literal sql expected throws';

throws_ok {
  $rs->populate([
    {
      artistid => 1,
      name => \"'foo'",
    },
    {
      artistid => 2,
      name => \"'bar'",
    }
  ]);
} qr/Inconsistent literal SQL value/, 'literal sql must be the same in all slices';

throws_ok {
  $rs->populate([
    {
      artistid => 1,
      name => \['?', [ {} => 'foo' ] ],
    },
    {
      artistid => 2,
      name => \"'bar'",
    }
  ]);
} qr/\QIncorrect value (expecting ARRAYREF-ref/, 'literal where literal+bind expected throws';

throws_ok {
  $rs->populate([
    {
      artistid => 1,
      name => \['?', [ { sqlt_datatype => 'foooo' } => 'foo' ] ],
    },
    {
      artistid => 2,
      name => \['?', [ {} => 'foo' ] ],
    }
  ]);
} qr/\QDiffering bind attributes on literal\/bind values not supported for column 'name'/, 'literal+bind with differing attrs throws';

lives_ok {
  $rs->populate([
    {
      artistid => 1,
      name => \['?', [ undef, 'foo' ] ],
    },
    {
      artistid => 2,
      name => \['?', [ {} => 'bar' ] ],
    }
  ]);
} 'literal+bind with semantically identical attrs works after normalization';

# test all kinds of population with stringified objects
# or with empty sets
warnings_like {
  my $rs = $schema->resultset('Artist')->search({}, { columns => [qw(name rank)], order_by => 'artistid' });

  # the stringification has nothing to do with the artist name
  # this is solely for testing consistency
  my $fn = Path::Class::File->new ('somedir/somefilename.tmp');
  my $fn2 = Path::Class::File->new ('somedir/someotherfilename.tmp');
  my $rank = Math::BigInt->new(42);

  my $args = {
    'stringifying objects after regular values' => { AoA => [
      [qw( name rank )],
      ( map { [ $_, $rank ] } (
        'supplied before stringifying objects',
        'supplied before stringifying objects 2',
        $fn,
        $fn2,
      )),
    ]},

    'stringifying objects before regular values' => { AoA => [
      [qw( rank name )],
      ( map { [ $rank, $_ ] } (
        $fn,
        $fn2,
        'supplied after stringifying objects',
        'supplied after stringifying objects 2',
      )),
    ]},

    'stringifying objects between regular values' => { AoA => [
      [qw( name rank )],
      ( map { [ $_, $rank ] } (
        'supplied before stringifying objects',
        $fn,
        $fn2,
        'supplied after stringifying objects',
      ))
    ]},

    'stringifying objects around regular values' => { AoA => [
      [qw( rank name )],
      ( map { [ $rank, $_ ] } (
        $fn,
        'supplied between stringifying objects',
        $fn2,
      ))
    ]},

    'single stringifying object' => { AoA => [
      [qw( rank name )],
      [ $rank, $fn ],
    ]},

    'empty set' => { AoA => [
      [qw( name rank )],
    ]},
  };

  # generate the AoH equivalent based on the AoAs above
  for my $bag (values %$args) {
    $bag->{AoH} = [];
    my @hdr = @{$bag->{AoA}[0]};
    for my $v ( @{$bag->{AoA}}[1..$#{$bag->{AoA}}] ) {
      push @{$bag->{AoH}}, my $h = {};
      @{$h}{@hdr} = @$v;
    }
  }

  local $Storable::canonical = 1;
  my $preimage = nfreeze($args);


  for my $tst (keys %$args) {
    for my $type (qw(AoA AoH)) {

      # test void ctx
      $rs->delete;
      $rs->populate($args->{$tst}{$type});
      is_deeply(
        $rs->all_hri,
        $args->{$tst}{AoH},
        "Populate() $tst in void context"
      );

      # test scalar ctx
      $rs->delete;
      my $dummy = $rs->populate($args->{$tst}{$type});
      is_deeply(
        $rs->all_hri,
        $args->{$tst}{AoH},
        "Populate() $tst in non-void context"
      );

      # test list ctx
      $rs->delete;
      my @dummy = $rs->populate($args->{$tst}{$type});
      is_deeply(
        $rs->all_hri,
        $args->{$tst}{AoH},
        "Populate() $tst in non-void context"
      );
    }

    # test create() as we have everything set up already
    $rs->delete;
    $rs->create($_) for @{$args->{$tst}{AoH}};

    is_deeply(
      $rs->all_hri,
      $args->{$tst}{AoH},
      "Create() $tst"
    );
  }

  ok (
    ($preimage eq nfreeze($args)),
    'Arguments fed to populate()/create() unchanged'
  );

  $rs->delete;
} [], 'Data integrity warnings gone as planned';

$schema->is_executed_sql_bind(
  sub {
   $schema->resultset('TwoKeys')->populate([{
      artist => 1,
      cd     => 5,
      fourkeys_to_twokeys => [{
            f_foo => 1,
            f_bar => 1,
            f_hello => 1,
            f_goodbye => 1,
            autopilot => 'a',
      },{
            f_foo => 2,
            f_bar => 2,
            f_hello => 2,
            f_goodbye => 2,
            autopilot => 'b',
      }]
   }])
  },
  [
    [ 'BEGIN' ],
    [ 'INSERT INTO twokeys ( artist, cd)
        VALUES ( ?, ? )',
      '__BULK_INSERT__'
    ],
    [ 'INSERT INTO fourkeys_to_twokeys ( autopilot, f_bar, f_foo, f_goodbye, f_hello, t_artist, t_cd)
        VALUES (
          ?, ?, ?, ?, ?,
          ( SELECT me.artist FROM twokeys me WHERE artist = ? AND cd = ? ),
          ( SELECT me.cd FROM twokeys me WHERE artist = ? AND cd = ? )
        )
      ',
      '__BULK_INSERT__'
    ],
    [ 'COMMIT' ],
  ],
  'multicol-PK has_many populate expected trace'
);

lives_ok ( sub {
  $schema->populate('CD', [
    {cdid => 10001, artist => $artist->id, title => 'Pretty Much Empty', year => 2011, tracks => []},
  ])
}, 'empty has_many relationship accepted by populate');

done_testing;
