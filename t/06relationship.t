use Test::More;

plan tests => 8;

use lib qw(t/lib);

use_ok('DBICTest');

# has_a test
my $cd = DBICTest::CD->retrieve(4);
my ($artist) = $cd->search_related('artist');
is($artist->name, 'Random Boy Band', 'has_a search_related ok');

# has_many test with an order_by clause defined
$artist = DBICTest::Artist->retrieve(1);
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

SKIP: {

  #skip "Relationship with invalid cols not yet checked", 1;

# try to add a bogus relationship using the wrong cols
eval {
    $artist->add_relationship(
        tracks => 'DBICTest::Track',
        { 'foreign.cd' => 'self.cdid' }
    );
};
like($@, qr/Unknown column/, 'failed when creating a rel with invalid key, ok');

} # End SKIP block

# another bogus relationship using no join condition
eval {
    $artist->add_relationship( tracks => 'DBICTest::Track' );
};
like($@, qr/join condition/, 'failed when creating a rel without join condition, ok');
