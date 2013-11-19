use strict;
use warnings;

use Test::More;
use Test::Exception;
use Test::Warn;
use lib qw(t/lib);
use DBICTest::Schema::Artist;
use Data::Query::ExprDeclare;
BEGIN {
  DBICTest::Schema::Artist->has_many(
    cds2 => 'DBICTest::Schema::CD',
    expr { $_->foreign->artist == $_->self->artistid }
  );
  DBICTest::Schema::Artist->has_many(
    cds2_pre2k => 'DBICTest::Schema::CD',
    expr {
      $_->foreign->artist == $_->self->artistid
      & $_->foreign->year < 2000
    }
  );
}
use DBICTest;
use DBIC::SqlMakerTest;

my $schema = DBICTest->init_schema();

my $mccrae = $schema->resultset('Artist')
                    ->find({ name => 'Caterwauler McCrae' });

is($mccrae->cds2->count, 3, 'CDs returned from expr join');

is($mccrae->cds2_pre2k->count, 2, 'CDs returned from expr w/cond');

$schema->source($_)->resultset_class('DBIx::Class::ResultSet::WithDQMethods')
  for qw(CD Tag);

my $cds = $schema->resultset('CD')
                 ->where(expr { $_->artist->name eq 'Caterwauler McCrae' });

is($cds->count, 3, 'CDs via join injection');

my $tags = $schema->resultset('Tag')
                  ->where(expr { $_->cd->artist->name eq 'Caterwauler McCrae' });

is($tags->count, 5, 'Tags via two step join injection');

done_testing;
