#!/usr/bin/env perl

use strict;
use warnings;

use Time::HiRes qw(gettimeofday tv_interval);
use Digest::SHA 'sha1_hex';

use lib 't/lib';
BEGIN { $ENV{DBICTEST_ANFANG_DEFANG} = 1 };
use DBICTest;

my $schema = DBICTest->init_schema(
  quote_names => 1,
  cursor_class => 'DBIx::Class::Cursor::Cached'
);

use Cache::FileCache;
my $c = Cache::FileCache->new({ namespace => 'SchemaClass' });

for my $i (1..9) {

  my $t0 = [gettimeofday];

  # getting a fresh rs makes sure we do not cache anything
  my $rs = $schema->resultset("Artist")->search({},{
    cache_object => $c,
    cache_for => 999999999999,
    prefetch => {
      cds => [
          ( { tracks => { cd_single => { artist => { cds => { tracks => 'cd_single' } } } } } ) x 50,
      ],
    },
    rows => 2,
  });

  my $q = ${$rs->as_query}->[0];

  print STDERR "@{[ length $q]} byte-long query generated (via as_query() in: ".tv_interval($t0) . " seconds (take $i)\n";

  # stuff below can be made even faster, but another time
  next;

  $t0 = [ gettimeofday ];

  my $x = $rs->all_hri;
  print STDERR "Got collapsed results (via HRI) in: ".tv_interval($t0) . " seconds (take $i)\n";
}
