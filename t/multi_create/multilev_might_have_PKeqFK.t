use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

sub mc_diag { diag (@_) if $ENV{DBIC_MULTICREATE_DEBUG} };

plan tests => 8;

my $schema = DBICTest->init_schema();

mc_diag (<<'DG');
* Test a multilevel might-have with a PK == FK in the might_have/has_many table

CD -> might have -> Artwork
                       \
                        \-> has_many \
                                      --> Artwork_to_Artist
                        /-> has_many /
                       /
                     Artist
DG

lives_ok (sub {
  my $someartist = $schema->resultset('Artist')->first;
  my $cd = $schema->resultset('CD')->create ({
    artist => $someartist,
    title => 'Music to code by until the cows come home',
    year => 2008,
    artwork => {
      artwork_to_artist => [
        { artist => { name => 'cowboy joe' } },
        { artist => { name => 'billy the kid' } },
      ],
    },
  });

  isa_ok ($cd, 'DBICTest::CD', 'Main CD object created');
  is ($cd->title, 'Music to code by until the cows come home', 'Correct CD title');

  my $art_obj = $cd->artwork;
  ok ($art_obj->has_column_loaded ('cd_id'), 'PK/FK present on artwork object');
  is ($art_obj->artists->count, 2, 'Correct artwork creator count via the new object');
  is_deeply (
    [ sort $art_obj->artists->get_column ('name')->all ],
    [ 'billy the kid', 'cowboy joe' ],
    'Artists named correctly when queried via object',
  );

  my $artwork = $schema->resultset('Artwork')->search (
    { 'cd.title' => 'Music to code by until the cows come home' },
    { join => 'cd' },
  )->single;
  is ($artwork->artists->count, 2, 'Correct artwork creator count via a new search');
  is_deeply (
    [ sort $artwork->artists->get_column ('name')->all ],
    [ 'billy the kid', 'cowboy joe' ],
    'Artists named correctly queried via a new search',
  );
}, 'multilevel might-have with a PK == FK in the might_have/has_many table ok');

1;
