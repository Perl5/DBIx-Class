use strict;
use warnings;

use Test::More;
use Test::Exception;
use Test::Warn;
use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;
use Data::Query::ExprDeclare;

my $schema = DBICTest->init_schema();

my $cds = $schema->resultset('CD');

my $restricted = $cds->search({}, { cache => 1, grep_cache => 1 })
                     ->search({ 'me.artist' => 1 });

is($restricted->count, 3, 'Count on restricted ok');

$restricted = $cds->search(
                      {},
                      { prefetch => 'artist', cache => 1, grep_cache => 1 }
                    )
                  ->search({ 'artist.name' => 'Caterwauler McCrae' });

is($restricted->count, 3, 'Count on restricted ok via join');

done_testing;
