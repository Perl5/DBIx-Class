BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

BEGIN { $ENV{DBIC_ASSERT_NO_ERRONEOUS_METAINSTANCE_USE} = 0 }

use strict;
use warnings;
no warnings 'qw';

use Test::More;

use DBICTest;

my $schema = DBICTest->init_schema;
my $rsrc = $schema->source("Artist");

is( (eval($_)||die $@), $rsrc, "Same source object after $_" ) for qw(
  $rsrc->resultset->result_source,
  $rsrc->resultset->next->result_source,
  $rsrc->resultset->next->result_source_instance,
  $schema->resultset("Artist")->result_source,
  $schema->resultset("Artist")->next->result_source,
  $schema->resultset("Artist")->next->result_source_instance,
);

done_testing;
