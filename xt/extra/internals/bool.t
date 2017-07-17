BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;

use Test::More;
use DBIx::Class::_Util qw( true false );
use Scalar::Util 'refaddr';

my @things = ( true, false, true, false, true, false );

for (my $i = 0; $i < $#things; $i++ ) {
  for my $j ( $i+1 .. $#things ) {
    cmp_ok
      refaddr( $things[$i] ),
        '!=',
      refaddr( $things[$j] ),
      "Boolean thingy '$i' distinct from '$j'",
    ;
  }
}

done_testing;
