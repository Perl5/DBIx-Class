use strict;
use warnings;  

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

eval "use DBD::SQLite";
plan skip_all => 'needs DBD::SQLite for testing' if $@;
plan tests => 1;

=cut
test fails with select => [ ], when the columns required for the relationship are absent

DBIC_TRACE=1:

  with select => [ qw / me.name cds.title ] (missing columns required for relationships)

  SELECT me.name, cds.title, cds.cdid, cds.artist, cds.title, cds.year, cds.genreid, cds.single_track
  FROM artist me
  LEFT JOIN cd cds ON cds.artist = me.artistid
  WHERE ( cds.title != ? )
  GROUP BY me.name, cds.title
  ORDER BY me.name, cds.title, cds.artist, cds.year: 'Generic Manufactured Singles'

  ****************************************************************************************************************************

  with no select => [ ]

  SELECT me.artistid, me.name, me.rank, me.charfield, cds.cdid, cds.artist, cds.title, cds.year, cds.genreid, cds.single_track
  FROM artist me
  LEFT JOIN cd cds ON cds.artist = me.artistid 
  WHERE ( cds.title != ? )
  GROUP BY me.artistid, me.name, me.rank, me.charfield
  ORDER BY me.name, cds.title, cds.artist, cds.year: 'Generic Manufactured Singles'

=cut


my $rs = $schema->resultset('Artist')->search({ 'cds.title' => { '!=' => 'Generic Manufactured Singles' } }, ## exists
                                              { prefetch => [ qw/ cds / ],
                                                join => [ qw/ cds / ],
                                                select => [ qw/ me.name cds.title / ],
                                                distinct => 1,
                                                order_by => [ qw/ me.name cds.title / ],
                                              });

lives_ok(sub { $rs->first }, 'Lives ok');
