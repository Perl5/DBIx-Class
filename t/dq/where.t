use strict;
use warnings;

use Test::More;
use Test::Exception;
use Test::Warn;
use lib qw(t/lib);
use DBICTest;
use Data::Query::ExprDeclare;
use DBIC::SqlMakerTest;

my $schema = DBICTest->init_schema();

$schema->source($_)->resultset_class('DBIx::Class::ResultSet::WithDQMethods')
  for qw(CD Tag);

my $cds = $schema->resultset('CD')
                 ->where(expr { $_->artist->name eq 'Caterwauler McCrae' });

is($cds->count, 3, 'CDs via join injection');

my $tags = $schema->resultset('Tag')
                  ->where(expr { $_->cd->artist->name eq 'Caterwauler McCrae' });

is($tags->count, 5, 'Tags via two step join injection');

done_testing;
