use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

plan tests => 1;

my $artist = $schema->resultset('Artist')->create({ name => 'Fred 1'});

my $cd = $schema->resultset('CD')->create({ artist => $artist,
                                            title => 'Some CD',
                                            year => 1996
                                          });

my $cd2 = $schema->resultset('CD')->create({ artist => 
                                   { name => 'Fred Bloggs' },
                                   title => 'Some CD',
                                   year => 1996
                                 });

is(ref $cd->artist, 'DBICTest::Artist', 'Created CD and Artist object');
