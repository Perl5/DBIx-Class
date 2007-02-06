use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

plan tests => 4;

my $cd2 = $schema->resultset('CD')->create({ artist => 
                                   { name => 'Fred Bloggs' },
                                   title => 'Some CD',
                                   year => 1996
                                 });

is(ref $cd2->artist, 'DBICTest::Artist', 'Created CD and Artist object');
is($cd2->artist->name, 'Fred Bloggs', 'Artist created correctly');

my $artist = $schema->resultset('Artist')->create({ name => 'Fred 2',
                                                     cds => [
                                                             { title => 'Music to code by',
                                                               year => 2007,
                                                             },
                                                             ],
                                                     });
is(ref $artist->cds->first, 'DBICTest::CD', 'Created Artist with CDs');
is($artist->cds->first->title, 'Music to code by', 'CD created correctly');
