use strict;
use warnings;

use Test::More;
use Test::Exception;
use Test::Warn;
use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;
use Data::Query::ExprDeclare;
use Data::Query::ExprHelpers;
use DBIx::Class::PerlRenderer::MangleStrings;

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

my $title_cond = \expr { $_->me->title eq 'Foo' }->{expr};

my $pred_normal = $cds->_construct_perl_predicate($title_cond);

bless(
  $schema->storage->perl_renderer,
  'DBIx::Class::PerlRenderer::MangleStrings',
);

my $pred_mangle = $cds->_construct_perl_predicate($title_cond);

foreach my $t ([ 'Foo', 1, 1 ], [ 'foo ', 0, 1 ]) {
  my $obj = $cds->new_result({ title => $t->[0] });
  foreach my $p ([ Normal => $pred_normal, 1 ], [ Mangle => $pred_mangle, 2 ]) {
    is(($p->[1]->($obj) ? 1 : 0), $t->[$p->[2]], join(': ', $p->[0], $t->[0]));
  }
}

done_testing;
