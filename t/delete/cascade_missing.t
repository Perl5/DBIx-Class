use strict;
use warnings;

use Test::More;
use Test::Warn;
use Test::Exception;

use lib 't/lib';
use DBICTest;

my $schema = DBICTest->init_schema();
$schema->_unregister_source('CD');

warnings_like {
  lives_ok {
    $_->delete for $schema->resultset('Artist')->all;
  } 'delete on rows with dangling rels lives';
} [
  # 12 == 3 artists * failed cascades:
  #   cds
  #   cds_unordered
  #   cds_very_very_very_long_relationship_name
  (qr/skipping cascad/i) x 9
], 'got warnings about cascading deletes';

done_testing;

