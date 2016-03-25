BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;

use Test::More;
use Test::Exception;

use DBICTest;
my $schema = DBICTest->init_schema();

# The nullchecks metadata for this collapse resolution is:
#
# mandatory => { 0 => 1 }
# from_first_encounter => [ [ 1, 2, 3 ] ]
# all_or_nothing => [ { 1 => 1, 2 => 1 } ]
#
my $rs = $schema->resultset('Artist')->search({}, {
  collapse => 1,
  join => { cds => 'tracks' },
  columns => [qw(
    me.artistid
    cds.artist
    cds.title
  ),
  { 'cds.tracks.title' => 'tracks.title' },
  ],
});

my @cases = (
  "'artistid'"
    => [ undef, 0, 0, undef ],

  "'artistid', 'cds.title'"
    => [ undef, 0, undef, undef ],

  "'artistid', 'cds.artist'"
    => [ undef, undef, 0, undef ],

  "'cds.artist'"
    => [ 0, undef, 0, 0 ],

  "'cds.title'"
    => [ 0, 0, undef, 0 ],

  # petrhaps need to report cds.title here as well, but that'll complicate checks even more...
  "'cds.artist'"
    => [ 0, undef, undef, 0 ],
);

while (@cases) {
  my ($err, $cursor) = splice @cases, 0, 2;

  $rs->{_stashed_rows} = [ $cursor ];

  throws_ok
    { $rs->next }
    qr/\Qthe following columns are declared (or defaulted to) non-nullable within DBIC but NULLs were retrieved from storage: $err within data row/,
    "Correct exception on non-nullable-yet-NULL $err"
  ;
}

done_testing;
