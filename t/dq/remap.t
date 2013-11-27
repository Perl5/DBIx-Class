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

my $schema = DBICTest->init_schema();

$schema->source($_)->resultset_class('DBIx::Class::ResultSet::WithDQMethods')
  for qw(CD Tag);

my $cds = $schema->resultset('CD');

throws_ok {
  $cds->_remap_identifiers(Identifier('name'))
} qr/Invalid name on me: name/;

is_deeply(
  [ $cds->_remap_identifiers(Identifier('title')) ],
  [ Identifier('me', 'title'), [] ],
  'Remap column on me'
);

throws_ok {
  $cds->_remap_identifiers(Identifier('artist'))
} qr/Invalid name on me: artist is a relationship/;

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

is_deeply(
  [ $cds->_remap_identifiers(Identifier('artist_id')) ],
  [ Identifier('me', 'artist'), [] ],
  'Remap column w/column name rename'
);

my $double_name = expr { $_->artist->name == $_->artist->name }->{expr};

is_deeply(
  [ $cds->_remap_identifiers($double_name) ],
  [ $double_name, [ { artist => {} } ] ],
  'Remap column on rel only adds rel once'
);

done_testing;
