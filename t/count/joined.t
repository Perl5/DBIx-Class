use strict;
use warnings;

use Test::More;

use lib qw(t/lib);

use DBICTest;

my $schema = DBICTest->init_schema();

my $cds = $schema->resultset("CD")->search({ cdid => 1 }, { join => { cd_to_producer => 'producer' } });
cmp_ok($cds->count, '>', 1, "extra joins explode entity count");

for my $arg (
  [ 'prefetch-collapsed has_many' => { prefetch => 'cd_to_producer' } ],
  [ 'distict-collapsed result' => { distinct => 1 } ],
  [ 'explicit collapse request' => { collapse => 1 } ],
) {
  for my $hri (0,1) {
    my $diag = $arg->[0] . ($hri ? ' with HRI' : '');

    my $rs = $cds->search({}, {
      %{$arg->[1]},
      $hri ? ( result_class => 'DBIx::Class::ResultClass::HashRefInflator' ) : (),
    });

    is
      $rs->count,
      1,
      "Count correct on $diag",
    ;

    is
      scalar $rs->all,
      1,
      "Amount of constructed objects matches count on $diag",
    ;
  }
}

# JOIN and LEFT JOIN issues mean that we've seen problems where counted rows and fetched rows are sometimes 1 higher than they should
# be in the related resultset.
my $artist=$schema->resultset('Artist')->create({name => 'xxx'});
is($artist->related_resultset('cds')->count(), 0, "No CDs found for a shiny new artist");
is(scalar($artist->related_resultset('cds')->all()), 0, "No CDs fetched for a shiny new artist");

my $artist_rs = $schema->resultset('Artist')->search({artistid => $artist->id});
is($artist_rs->related_resultset('cds')->count(), 0, "No CDs counted for a shiny new artist using a resultset search");
is(scalar($artist_rs->related_resultset('cds')->all), 0, "No CDs fetched for a shiny new artist using a resultset search");

done_testing;
