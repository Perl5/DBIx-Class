use strict;
use warnings;

use Test::More;
use Test::Exception;
use Test::Warn;
use lib qw(t/lib);
use Data::Query::ExprDeclare;
use Data::Query::ExprHelpers;
use DBICTest;
use DBIC::SqlMakerTest;

my $schema = DBICTest->init_schema();

$schema->source($_)->resultset_class('DBIx::Class::ResultSet::WithDQMethods')
  for qw(CD Tag);

my $cds = $schema->resultset('CD');

is_deeply(
  [ $cds->_remap_identifiers(Identifier('name')) ],
  [ Identifier('me', 'name'), [] ],
  'Remap column on me'
);

is_deeply(
  [ $cds->_remap_identifiers(Identifier('artist', 'name')) ],
  [ Identifier('artist', 'name'), [ { artist => {} } ] ],
  'Remap column on rel'
);

is_deeply(
  [ $cds->search({}, { join => { single_track => { cd => 'artist' } } })
        ->_remap_identifiers(Identifier('artist', 'name')) ],
  [ Identifier('artist_2', 'name'), [ { artist => {} } ] ],
  'Remap column on rel with re-alias'
);

done_testing;
