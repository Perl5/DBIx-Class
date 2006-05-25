use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

plan tests => 34;

my $artistid = 1;
my $title    = 'UNIQUE Constraint';

my $cd1 = $schema->resultset('CD')->find_or_create({
  artist => $artistid,
  title  => $title,
  year   => 2005,
});

my $cd2 = $schema->resultset('CD')->find(
  {
    artist => $artistid,
    title  => $title,
  },
  { key => 'artist_title' }
);

is($cd2->get_column('artist'), $cd1->get_column('artist'), 'find by specific key: artist is correct');
is($cd2->title, $cd1->title, 'title is correct');
is($cd2->year, $cd1->year, 'year is correct');

my $cd3 = $schema->resultset('CD')->find($artistid, $title, { key => 'artist_title' });

is($cd3->get_column('artist'), $cd1->get_column('artist'), 'find by specific key, ordered columns: artist is correct');
is($cd3->title, $cd1->title, 'title is correct');
is($cd3->year, $cd1->year, 'year is correct');

my $cd4 = $schema->resultset('CD')->update_or_create(
  {
    artist => $artistid,
    title  => $title,
    year   => 2007,
  },
);

ok(! $cd4->is_changed, 'update_or_create without key: row is clean');
is($cd4->cdid, $cd2->cdid, 'cdid is correct');
is($cd4->get_column('artist'), $cd2->get_column('artist'), 'artist is correct');
is($cd4->title, $cd2->title, 'title is correct');
is($cd4->year, 2007, 'updated year is correct');

my $cd5 = $schema->resultset('CD')->update_or_create(
  {
    artist => $artistid,
    title  => $title,
    year   => 2007,
  },
  { key => 'artist_title' }
);

ok(! $cd5->is_changed, 'update_or_create by specific key: row is clean');
is($cd5->cdid, $cd2->cdid, 'cdid is correct');
is($cd5->get_column('artist'), $cd2->get_column('artist'), 'artist is correct');
is($cd5->title, $cd2->title, 'title is correct');
is($cd5->year, 2007, 'updated year is correct');

my $cd6 = $schema->resultset('CD')->update_or_create(
  {
    cdid   => $cd2->cdid,
    artist => 1,
    title  => $cd2->title,
    year   => 2005,
  },
  { key => 'primary' }
);

ok(! $cd6->is_changed, 'update_or_create by PK: row is clean');
is($cd6->cdid, $cd2->cdid, 'cdid is correct');
is($cd6->get_column('artist'), $cd2->get_column('artist'), 'artist is correct');
is($cd6->title, $cd2->title, 'title is correct');
is($cd6->year, 2005, 'updated year is correct');

my $cd7 = $schema->resultset('CD')->find_or_create(
  {
    artist => $artistid,
    title  => $title,
    year   => 2010,
  },
  { key => 'artist_title' }
);

is($cd7->cdid, $cd1->cdid, 'find_or_create by specific key: cdid is correct');
is($cd7->get_column('artist'), $cd1->get_column('artist'), 'artist is correct');
is($cd7->title, $cd1->title, 'title is correct');
is($cd7->year, $cd1->year, 'year is correct');

my $artist = $schema->resultset('Artist')->find($artistid);
my $cd8 = $artist->find_or_create_related('cds',
  {
    artist => $artistid,
    title  => $title,
    year   => 2020,
  },
  { key => 'artist_title' }
);

is($cd8->cdid, $cd1->cdid, 'find_or_create related by specific key: cdid is correct');
is($cd8->get_column('artist'), $cd1->get_column('artist'), 'artist is correct');
is($cd8->title, $cd1->title, 'title is correct');
is($cd8->year, $cd1->year, 'year is correct');

my $cd9 = $artist->update_or_create_related('cds',
  {
    artist => $artistid,
    title  => $title,
    year   => 2021,
  },
  { key => 'artist_title' }
);

ok(! $cd9->is_changed, 'update_or_create by specific key: row is clean');
is($cd9->cdid, $cd1->cdid, 'cdid is correct');
is($cd9->get_column('artist'), $cd1->get_column('artist'), 'artist is correct');
is($cd9->title, $cd1->title, 'title is correct');
is($cd9->year, 2021, 'year is correct');

