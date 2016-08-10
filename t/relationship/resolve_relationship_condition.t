BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;

use Test::More;
use Test::Exception;


use DBICTest;

my $schema = DBICTest->init_schema();

for (
  { year => [1,2] },
  { year => ['-and',1,2] },
  { -or => [ year => 1, year => 2 ] },
  { -and => [ year => 1, year => 2 ] },
) {
  throws_ok {
    $schema->source('Track')->_resolve_relationship_condition(
      rel_name => 'cd_cref_cond',
      self_alias => 'me',
      foreign_alias => 'cd',
      foreign_values => $_
    );
  } qr/
    \Qis not a column on related source 'CD'\E
      |
    \Qsupplied value for foreign column 'year' is not a direct equivalence expression\E
      |
    \QThe key '-\E \w+ \Q' supplied as part of 'foreign_values' during relationship resolution must be a column name, not a function\E
  /x;
}

done_testing;
