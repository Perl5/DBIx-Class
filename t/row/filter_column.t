use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();
DBICTest::Schema::Artist->load_components('FilterColumn');
DBICTest::Schema::Artist->filter_column(rank => {
  filter   => sub { $_[1] * 2 },
  unfilter => sub { $_[1] / 2 },
});
Class::C3->reinitialize();

my $artist = $schema->resultset('Artist')->create( { rank => 20 } );

# this should be using the cursor directly, no inflation/processing of any sort
my ($raw_db_rank) = $schema->resultset('Artist')
                             ->search ($artist->ident_condition)
                               ->get_column('rank')
                                ->_resultset
                                 ->cursor
                                  ->next;

is ($raw_db_rank, 10, 'INSERT: correctly unfiltered on insertion');

for my $reloaded (0, 1) {
  my $test = $reloaded ? 'reloaded' : 'stored';
  $artist->discard_changes if $reloaded;

  is( $artist->rank , 20, "got $test filtered rank" );
}

$artist->update;
$artist->discard_changes;
is( $artist->rank , 20, "got filtered rank" );

$artist->update ({ rank => 40 });
($raw_db_rank) = $schema->resultset('Artist')
                             ->search ($artist->ident_condition)
                               ->get_column('rank')
                                ->_resultset
                                 ->cursor
                                  ->next;
is ($raw_db_rank, 20, 'UPDATE: correctly unflitered on update');

$artist->discard_changes;
$artist->rank(40);
ok( !$artist->is_column_changed('rank'), 'column is not dirty after setting the same value' );

done_testing;
