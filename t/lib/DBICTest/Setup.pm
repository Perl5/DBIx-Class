use strict;
use warnings;
use DBICTest;

my $schema = DBICTest->initialise;

# $schema->storage->on_connect_do([ "PRAGMA synchronous = OFF" ]);

my $dbh = $schema->storage->dbh;

if ($ENV{"DBICTEST_SQLT_DEPLOY"}) {
  $schema->deploy;
} else {
  open IN, "t/lib/sqlite.sql";

  my $sql;

  { local $/ = undef; $sql = <IN>; }

  close IN;

  $dbh->do($_) for split(/;\n/, $sql);
}

$schema->storage->dbh->do("PRAGMA synchronous = OFF");

$schema->populate('Artist', [
  [ qw/artistid name/ ],
  [ 1, 'Caterwauler McCrae' ],
  [ 2, 'Random Boy Band' ],
  [ 3, 'We Are Goth' ],
]);

$schema->populate('CD', [
  [ qw/cdid artist title year/ ],
  [ 1, 1, "Spoonful of bees", 1999 ],
  [ 2, 1, "Forkful of bees", 2001 ],
  [ 3, 1, "Caterwaulin' Blues", 1997 ],
  [ 4, 2, "Generic Manufactured Singles", 2001 ],
  [ 5, 3, "Come Be Depressed With Us", 1998 ],
]);

$schema->populate('LinerNotes', [
  [ qw/liner_id notes/ ],
  [ 2, "Buy Whiskey!" ],
  [ 4, "Buy Merch!" ],
  [ 5, "Kill Yourself!" ],
]);

$schema->populate('Tag', [
  [ qw/tagid cd tag/ ],
  [ 1, 1, "Blue" ],
  [ 2, 2, "Blue" ],
  [ 3, 3, "Blue" ],
  [ 4, 5, "Blue" ],
  [ 5, 2, "Cheesy" ],
  [ 6, 4, "Cheesy" ],
  [ 7, 5, "Cheesy" ],
  [ 8, 2, "Shiny" ],
  [ 9, 4, "Shiny" ],
]);

$schema->populate('TwoKeys', [
  [ qw/artist cd/ ],
  [ 1, 1 ],
  [ 1, 2 ],
  [ 2, 2 ],
]);

$schema->populate('FourKeys', [
  [ qw/foo bar hello goodbye/ ],
  [ 1, 2, 3, 4 ],
  [ 5, 4, 3, 6 ],
]);

$schema->populate('OneKey', [
  [ qw/id artist cd/ ],
  [ 1, 1, 1 ],
  [ 2, 1, 2 ],
  [ 3, 2, 2 ],
]);

$schema->populate('SelfRef', [
  [ qw/id name/ ],
  [ 1, 'First' ],
  [ 2, 'Second' ],
]);

$schema->populate('SelfRefAlias', [
  [ qw/self_ref alias/ ],
  [ 1, 2 ]
]);

$schema->populate('ArtistUndirectedMap', [
  [ qw/id1 id2/ ],
  [ 1, 2 ]
]);

$schema->populate('Producer', [
  [ qw/producerid name/ ],
  [ 1, 'Matt S Trout' ],
  [ 2, 'Bob The Builder' ],
  [ 3, 'Fred The Phenotype' ],
]);

$schema->populate('CD_to_Producer', [
  [ qw/cd producer/ ],
  [ 1, 1 ],
  [ 1, 2 ],
  [ 1, 3 ],
]);

$schema->populate('TreeLike', [
  [ qw/id parent name/ ],
  [ 1, 0, 'foo'  ],
  [ 2, 1, 'bar'  ],
  [ 3, 2, 'baz'  ],
  [ 4, 3, 'quux' ],
]);

$schema->populate('Track', [
  [ qw/trackid cd  position title/ ],
  [ 4, 2, 1, "Stung with Success"],
  [ 5, 2, 2, "Stripy"],
  [ 6, 2, 3, "Sticky Honey"],
  [ 7, 3, 1, "Yowlin"],
  [ 8, 3, 2, "Howlin"],
  [ 9, 3, 3, "Fowlin"],
  [ 10, 4, 1, "Boring Name"],
  [ 11, 4, 2, "Boring Song"],
  [ 12, 4, 3, "No More Ideas"],
  [ 13, 5, 1, "Sad"],
  [ 14, 5, 2, "Under The Weather"],
  [ 15, 5, 3, "Suicidal"],
  [ 16, 1, 1, "The Bees Knees"],
  [ 17, 1, 2, "Apiary"],
  [ 18, 1, 3, "Beehind You"],
]);

1;
