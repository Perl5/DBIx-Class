use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $link = $schema->resultset ('Link')->create ({
  url => 'loldogs!',
  bookmarks => [
    { link => 'Mein Hund ist schwul'},
    { link => 'Mein Hund ist schwul'},
  ]
});
is ($link->bookmarks->count, 2, "Two identical default-insert has_many's created");


$link = $schema->resultset ('Link')->create ({
  url => 'lolcats!',
  bookmarks => [
    {},
    {},
  ]
});
is ($link->bookmarks->count, 2, "Two identical default-insert has_many's created");

done_testing;
