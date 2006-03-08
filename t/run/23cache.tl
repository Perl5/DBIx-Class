sub run_tests {
my $schema = shift;

eval "use DBD::SQLite";
plan skip_all => 'needs DBD::SQLite for testing' if $@;
plan tests => 12;

my $rs = $schema->resultset("Artist")->search(
  { artistid => 1 }
);

my $artist = $rs->first;

is( scalar @{ $rs->get_cache }, 0, 'cache is not populated without cache attribute' );

$rs = $schema->resultset("Artist")->search(
  { 'artistid' => 1 },
  {
    join => [ qw/ cds /],
    prefetch => [qw/ cds /],
  }
);

use Data::Dumper; $Data::Dumper::Deparse = 1;

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
is($selects, 1, 'only one SQL statement executed');

# make sure related_resultset is deleted after object is updated
$artist->set_column('name', 'New Name');
$artist->update();

is( scalar keys %{$artist->{related_resultsets}}, 0, 'related resultsets deleted after update' );

# todo: make sure caching works with nested prefetch e.g. $artist->cds->tracks
$rs = $schema->resultset("Artist")->search(
  { artistid => 1 },
  {
    join => { cds => 'tags' },
    prefetch => {
      cds => 'tags'
    },
  }
);

# SELECT count for nested has_many prefetch
unlink 't/var/dbic.trace' if -e 't/var/dbic.trace';
DBI->trace(1, 't/var/dbic.trace');

$artist = ($rs->all)[0];

# count the SELECTs
DBI->trace(0, undef);
$selects = 0;
$trace = IO::File->new('t/var/dbic.trace', '<') 
    or die "Unable to read trace file";
while (<$trace>) {
    $selects++ if /SELECT/;
}
$trace->close;
unlink 't/var/dbic.trace';
is($selects, 1, 'only one SQL statement executed');

my @objs;
#$artist = $rs->find(1);

unlink 't/var/dbic.trace' if -e 't/var/dbic.trace';
DBI->trace(1, 't/var/dbic.trace');

my $cds = $artist->cds;
my $tags = $cds->next->tags;
while( my $tag = $tags->next ) {
  push @objs, $tag->tagid; #warn "tag:", $tag->ID, " => ", $tag->tag;
}

is_deeply( \@objs, [ 3 ], 'first cd has correct tags' );

$tags = $cds->next->tags;
@objs = ();
while( my $tag = $tags->next ) {
  push @objs, $tag->id; #warn "tag: ", $tag->ID;
}

is_deeply( \@objs, [ 2, 5, 8 ], 'second cd has correct tags' );

# count the SELECTs
DBI->trace(0, undef);
$selects = 0;
$trace = IO::File->new('t/var/dbic.trace', '<') 
    or die "Unable to read trace file";
while (<$trace>) {
    $selects++ if /SELECT/;
}
$trace->close;
unlink 't/var/dbic.trace';

is( $selects, 0, 'no additional SQL statements while checking nested data' );

}

1;
