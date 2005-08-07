use Test::More;

plan tests => 14;

use lib qw(t/lib);

use_ok('DBICTest');

# has_a test
my $cd = DBICTest::CD->find(4);
my ($artist) = $cd->search_related('artist');
is($artist->name, 'Random Boy Band', 'has_a search_related ok');

# has_many test with an order_by clause defined
$artist = DBICTest::Artist->find(1);
is( ($artist->search_related('cds'))[1]->title, 'Spoonful of bees', 'has_many search_related with order_by ok' );

# search_related with additional abstract query
my @cds = $artist->search_related('cds', { title => { like => '%of%' } } );
is( $cds[1]->title, 'Forkful of bees', 'search_related with abstract query ok' );

# creating a related object
$artist->create_related( 'cds', {
    title => 'Big Flop',
    year => 2005,
} );
is( ($artist->search_related('cds'))[3]->title, 'Big Flop', 'create_related ok' );

# count_related
is( $artist->count_related('cds'), 4, 'count_related ok' );

# set_from_related
my $track = DBICTest::Track->create( {
  trackid => 1,
  cd => 3,
  position => 98,
  title => 'Hidden Track'
} );
$track->set_from_related( cd => $cd );
is( $track->cd, 4, 'set_from_related ok' );

# update_from_related, the same as set_from_related, but it calls update afterwards
$track = DBICTest::Track->create( {
  trackid => 2,
  cd => 3,
  position => 99,
  title => 'Hidden Track'
} );
$track->update_from_related( cd => $cd );
is( (DBICTest::Track->search( cd => 4, position => 99 ))[0]->cd, 4, 'update_from_related ok' );

# find_or_create_related with an existing record
$cd = $artist->find_or_create_related( 'cds', { title => 'Big Flop' } );
is( $cd->year, 2005, 'find_or_create_related on existing record ok' );

# find_or_create_related creating a new record
$cd = $artist->find_or_create_related( 'cds', {
  title => 'Greatest Hits',
  year => 2006,
} );
is( $cd->title, 'Greatest Hits', 'find_or_create_related new record ok' );
@cds = $artist->search_related('cds');
is( ($artist->search_related('cds'))[4]->title, 'Greatest Hits', 'find_or_create_related new record search ok' );

SKIP: {
    #skip 'Need to add delete_related', 1;
    # delete_related
    $artist->delete_related( cds => { title => 'Greatest Hits' });
    cmp_ok( DBICTest::CD->search( title => 'Greatest Hits' ), '==', 0, 'delete_related ok' );
};

# try to add a bogus relationship using the wrong cols
eval {
    $artist->add_relationship(
        tracks => 'DBICTest::Track',
        { 'foreign.cd' => 'self.cdid' }
    );
};
like($@, qr/Unknown column/, 'failed when creating a rel with invalid key, ok');

# another bogus relationship using no join condition
eval {
    $artist->add_relationship( tracks => 'DBICTest::Track' );
};
like($@, qr/join condition/, 'failed when creating a rel without join condition, ok');
