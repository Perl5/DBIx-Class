use strict;
use warnings;

use Test::More;

#----------------------------------------------------------------------
# Make sure subclasses can be themselves subclassed
#----------------------------------------------------------------------

use lib 't/cdbi/testlib';
use Film;

INIT { @Film::Threat::ISA = qw/Film/; }

ok(Film::Threat->db_Main->ping, 'subclass db_Main()');
is_deeply [ sort Film::Threat->columns ], [ sort Film->columns ],
  'has the same columns';

my $bt = Film->create_test_film;
ok my $btaste = Film::Threat->retrieve('Bad Taste'), "subclass retrieve";
isa_ok $btaste => "Film::Threat";
isa_ok $btaste => "Film";
is $btaste->Title, 'Bad Taste', 'subclass get()';

done_testing;
