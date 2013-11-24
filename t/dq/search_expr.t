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

my $mccrae = $schema->resultset('Artist')
                    ->find({ name => 'Caterwauler McCrae' });

my @cds = $schema->resultset('CD')
                 ->search(expr { $_->artist == $mccrae->artistid });

is(@cds, 3, 'CDs returned from expr search by artistid');

my @years = $schema->resultset('CD')
                   ->search(expr { $_->year < 2000 })
                   ->get_column('year')
                   ->all;

is_deeply([ sort @years ], [ 1997, 1998, 1999 ], 'Years for < search');

my $tag_cond = expr { $_->tag eq 'Blue' };

is($schema->resultset('Tag')->search($tag_cond)->count, 4, 'Simple tag cond');

$tag_cond &= expr { $_->cd < 4 };

is($schema->resultset('Tag')->search($tag_cond)->count, 3, 'Combi tag cond');

done_testing;
