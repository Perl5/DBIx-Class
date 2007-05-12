use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;

plan tests => 18;

my $schema = DBICTest->init_schema();
my $rs = $schema->resultset('Artist');

$rs->populate( [
  { artistid => 4, name => 'Manufactured Crap', cds => [ 
      { title => 'My First CD', year => 2006 },
      { title => 'Yet More Tweeny-Pop crap', year => 2007 },
    ] 
  },
  { artistid => 5, name => 'Angsty-Whiny Girl', cds => [
      { title => 'My parents sold me to a record company' ,year => 2005 },
      { title => 'Why Am I So Ugly?', year => 2006 },
      { title => 'I Got Surgery and am now Popular', year => 2007 }

    ]
  },
  { name => 'Like I Give a Damn' }

] );

my $artist = $rs->find(4);

ok($artist, 'Found artist');
is($artist->name, 'Manufactured Crap');
is($artist->cds->count, 2, 'Has CDs');

my @cds = $artist->cds;

is($cds[0]->title, 'My First CD', 'A CD');
is($cds[0]->year,  2006, 'Published in 2006');

is($cds[1]->title, 'Yet More Tweeny-Pop crap', 'Another crap CD');
is($cds[1]->year,  2007, 'Published in 2007');

$artist = $rs->find(5);
ok($artist, 'Found artist');
is($artist->name, 'Angsty-Whiny Girl');
is($artist->cds->count, 3, 'Has CDs');

@cds = $artist->cds;


is($cds[0]->title, 'My parents sold me to a record company', 'A CD');
is($cds[0]->year,  2005, 'Published in 2005');

is($cds[1]->title, 'Why Am I So Ugly?', 'A Coaster');
is($cds[1]->year,  2006, 'Published in 2006');

is($cds[2]->title, 'I Got Surgery and am now Popular', 'Selling un-attainable dreams');
is($cds[2]->year,  2007, 'Published in 2007');

$artist = $rs->search({name => 'Like I Give A Damn'})->single;
ok($artist);

is($artist->cds->count, 0, 'No CDs');

