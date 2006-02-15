sub run_tests {
my $schema = shift;

eval "use DBD::SQLite";
plan skip_all => 'needs DBD::SQLite for testing' if $@;
plan tests => 8;

my $rs = $schema->resultset("Artist")->search(
  { artistid => 1 }
);

my $artist = $rs->first;

is( scalar @{ $rs->get_cache }, 0, 'cache is not populated without cache attribute' );

$rs = $schema->resultset("Artist")->search(
  { 'artistid' => 1 },
  {
    prefetch => [qw/ cds /],
    cache => 1,
  }
);

# use Data::Dumper; $Data::Dumper::Deparse = 1;

# start test for prefetch SELECT count
unlink 't/var/dbic.trace' if -e 't/var/dbic.trace';
DBI->trace(1, 't/var/dbic.trace');

$artist = $rs->first;
$rs->reset();

# make sure artist contains a related resultset for cds
is( ref $artist->{related_resultsets}->{cds}, 'DBIx::Class::ResultSet', 'artist has a related_resultset for cds' );

# check if $artist->cds->get_cache is populated
is( scalar @{$artist->cds->get_cache}, 3, 'cache for artist->cds contains correct number of records');

# ensure that $artist->cds returns correct number of objects
is( scalar ($artist->cds), 3, 'artist->cds returns correct number of objects' );

# ensure that $artist->cds->count returns correct value
is( $artist->cds->count, 3, 'artist->cds->count returns correct value' );

# ensure that $artist->count_related('cds') returns correct value
is( $artist->count_related('cds'), 3, 'artist->count_related returns correct value' );

# count the SELECTs
DBI->trace(0, undef);
my $selects = 0;
my $trace = IO::File->new('t/var/dbic.trace', '<') 
    or die "Unable to read trace file";
while (<$trace>) {
    $selects++ if /SELECT/;
}
$trace->close;
unlink 't/var/dbic.trace';
is($selects, 2, 'only one SQL statement for each cached table');

# make sure related_resultset is deleted after object is updated
$artist->set_column('name', 'New Name');
$artist->update();

is( scalar keys %{$artist->{related_resultsets}}, 0, 'related resultsets deleted after update' );

# todo: make sure caching works with nested prefetch e.g. $artist->cds->tracks
$rs = $schema->resultset("Artist")->search(
  { artistid => 1 },
  {
    prefetch => {
      cds => 'tags'
    },
    cache => 1
  }
);

}

1;
