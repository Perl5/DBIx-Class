use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

plan tests => 23;

my $schema = DBICTest->init_schema();

# The map below generates stuff like:
#   [ qw/artistid name/ ],
#   [ 4, "b" ],
#   [ 5, "c" ],
#   ...
#   [ 9999, "ntm" ],
#   [ 10000, "ntn" ],

my $start_id = 'populateXaaaaaa';
my $rows = 10;
my $offset = 3;

$schema->populate('Artist', [ [ qw/artistid name/ ], map { [ ($_ + $offset) => $start_id++ ] } ( 1 .. $rows ) ] );
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
}, qr/columns .+ are not unique for populate slice.+$ex_title/ms, 'Readable exception thrown for failed populate');

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

