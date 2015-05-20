use warnings;
use strict;

use Benchmark qw( cmpthese :hireswallclock);
use Sereal;
use Devel::Dwarn;

my ($semicol, $comma) = map {
  my $src = do { local (@ARGV, $/) = $_; <> };
  eval "sub { use strict; use warnings; use warnings FATAL => 'uninitialized'; $src }" or die $@;
} qw( semicol.src comma.src );

my $enc = Sereal::Encoder->new;
my $dec = Sereal::Decoder->new;

for my $iters ( 100, 10_000, 100_000 ) {
  my $dataset = [];
  push @$dataset, [ (scalar @$dataset) x 11 ]
    while @$dataset < $iters;

  my $ice = $enc->encode($dataset);

  print "\nTiming $iters 'rows'...\n";
  cmpthese( -10, {
    semicol => sub { $semicol->($dec->decode($ice)) },
    comma => sub { $comma->($dec->decode($ice)) },
  })
}
