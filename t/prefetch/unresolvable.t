use strict;
use warnings;  

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

plan tests => 5;

my $schema = DBICTest->init_schema();

lives_ok(sub {

#  use Data::Dumper;
#  warn Dumper [$schema->resultset('Artist')->search ({}, { prefetch => 'cds' })->hri_dump->all];


  # while cds.* will be selected anyway (prefetch currently forces the result of _resolve_prefetch)
  # only the requested me.name column will be fetched. This somehow does work on 08010 (tested)

  # reference sql with select => [...]
  #   SELECT me.name, cds.title, cds.cdid, cds.artist, cds.title, cds.year, cds.genreid, cds.single_track FROM ...

  my $rs = $schema->resultset('Artist')->search(
    { 'cds.title' => { '!=', 'Generic Manufactured Singles' } },
    {
      prefetch => [ qw/ cds / ],
      order_by => [ { -desc => 'me.name' }, 'cds.title' ],
      select => [ qw/ me.name cds.title / ],
    }
  );

  is ($rs->count, 2, 'Correct number of collapsed artists');
  my $we_are_goth = $rs->first;
  is ($we_are_goth->name, 'We Are Goth', 'Correct first artist');
  is ($we_are_goth->cds->count, 1, 'Correct number of CDs for first artist');
  is ($we_are_goth->cds->first->title, 'Come Be Depressed With Us', 'Correct cd for artist');

});
