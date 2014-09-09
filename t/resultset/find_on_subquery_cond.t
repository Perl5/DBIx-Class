use strict;
use warnings;

use Test::More;
use Test::Exception;

use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();
my $rs = $schema->resultset('Artist');

for my $id (
  2,
  \' = 2 ',
  \[ '= ?', 2 ],
) {
  lives_ok {
    is( $rs->find({ artistid => $id })->id, 2 )
  } "Correctly found artist with id of @{[ explain $id ]}";
}

for my $id (
  2,
  \'2',
  \[ '?', 2 ],
) {
  my $cond = { artistid => { '=', $id } };
  lives_ok {
    is( $rs->find($cond)->id, 2 )
  } "Correctly found artist with id of @{[ explain $cond ]}";
}

done_testing;
