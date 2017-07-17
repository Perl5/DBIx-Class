BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;

use Test::More;

use DBICTest;

my $schema = DBICTest->init_schema();

cmp_ok($schema->resultset("CD")->count({ 'artist.name' => 'Caterwauler McCrae' },
                           { join => 'artist' }),
           '==', 3, 'Count by has_a ok');

cmp_ok($schema->resultset("CD")->count({ 'tags.tag' => 'Blue' }, { join => 'tags' }),
           '==', 4, 'Count by has_many ok');

cmp_ok($schema->resultset("CD")->count(
           { 'liner_notes.notes' => { '!=' =>  undef } },
           { join => 'liner_notes' }),
           '==', 3, 'Count by might_have ok');

cmp_ok($schema->resultset("CD")->count(
           { 'year' => { '>', 1998 }, 'tags.tag' => 'Cheesy',
               'liner_notes.notes' => { 'like' => 'Buy%' } },
           { join => [ qw/tags liner_notes/ ] } ),
           '==', 2, "Mixed count ok");

done_testing;
