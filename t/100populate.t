use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;
use Path::Class::File ();
use List::Util qw/shuffle/;

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


## make sure populate -> insert_bulk honors fields/orders in void context
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

# populate with literals
{
  my $rs = $schema->resultset('Link');
  $rs->delete;

  # test insert_bulk with all literal sql (no binds)

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

  # test insert_bulk with all literal/bind sql
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

  # test insert_bulk with mix literal and literal/bind
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
    url => \[ '? || ?', [ {} => 'cpan.org_' ], [ undef, $_ ] ],
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
} qr/\Qexecute_for_fetch() aborted with 'datatype mismatch\E\b/, 'bad slice';

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

# the stringification has nothing to do with the artist name
# this is solely for testing consistency
my $fn = Path::Class::File->new ('somedir/somefilename.tmp');
my $fn2 = Path::Class::File->new ('somedir/someotherfilename.tmp');

lives_ok {
  $rs->populate([
    {
      name => 'supplied before stringifying object',
    },
    {
      name => $fn,
    }
  ]);
} 'stringifying objects pass through';

# ... and vice-versa.

lives_ok {
  $rs->populate([
    {
      name => $fn2,
    },
    {
      name => 'supplied after stringifying object',
    },
  ]);
} 'stringifying objects pass through';

for (
  $fn,
  $fn2,
  'supplied after stringifying object',
  'supplied before stringifying object'
) {
  my $row = $rs->find ({name => $_});
  ok ($row, "Stringification test row '$_' properly inserted");
}

$rs->delete;

# test stringification with ->create rather than Storage::insert_bulk as well

lives_ok {
  my @dummy = $rs->populate([
    {
      name => 'supplied before stringifying object',
    },
    {
      name => $fn,
    }
  ]);
} 'stringifying objects pass through';

# ... and vice-versa.

lives_ok {
  my @dummy = $rs->populate([
    {
      name => $fn2,
    },
    {
      name => 'supplied after stringifying object',
    },
  ]);
} 'stringifying objects pass through';

for (
  $fn,
  $fn2,
  'supplied after stringifying object',
  'supplied before stringifying object'
) {
  my $row = $rs->find ({name => $_});
  ok ($row, "Stringification test row '$_' properly inserted");
}

lives_ok {
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
} 'multicol-PK has_many populate works';

lives_ok ( sub {
  $schema->populate('CD', [
    {cdid => 10001, artist => $artist->id, title => 'Pretty Much Empty', year => 2011, tracks => []},
  ])
}, 'empty has_many relationship accepted by populate');

done_testing;
