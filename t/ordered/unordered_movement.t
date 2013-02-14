use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $cd = $schema->resultset('CD')->next;

lives_ok {
  $cd->tracks->delete;

  my @tracks = map
    { $cd->create_related('tracks', { title => "t_$_", position => $_ }) }
    (4,2,5,1,3)
  ;

  for (@tracks) {
    $_->discard_changes;
    $_->delete;
  }
} 'Creation/deletion of out-of order tracks successful';

done_testing;
