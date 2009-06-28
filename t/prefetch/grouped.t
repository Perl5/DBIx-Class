#!/usr/bin/perl

use strict;
use warnings;
use Test::More 'no_plan';

use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;
use DBIC::DebugObj;

#plan tests => 6;

my $schema = DBICTest->init_schema( deploy_args => { add_drop_table => 1 } );

## CD has_many Tracks
## Track belongs_to CD

my $cd_count = $schema->resultset('CD')->count;
is($cd_count, 5, 'Plain CDs count');
# print STDERR "CDs: $cd_count\n";

my $cd_tracks = $schema->resultset('CD')->related_resultset('tracks')->count;
is($cd_tracks, 15, 'Tracks for CDs');
# print STDERR "CD Tracks: $cd_tracks\n";

my $count_per_cd = $schema->resultset('Track')->
    search({}, 
           { 'select' => [ 'me.cd', { count => 'me.trackid', } ],
             'as' =>     [ 'cd', 'cd_count' ],
             'group_by' => ['me.cd'],
#    [ 'me.cd', 'cd_count' ],
           });

while (my $cnt = $count_per_cd->next) {
    is($cnt->get_column('cd_count'), 3, 'CDs per track ' . $cnt->get_column('cd'));
#    print STDERR "CD: " . $cnt->get_column('cd') . " count: " . $cnt->get_column('cd_count') . "\n";
}

$count_per_cd->reset;
while (my $trcnt = $count_per_cd->next) {
#    print STDERR "CD: " . $trcnt->get_column('cd') . " count: " . $trcnt->get_column('cd_count') . "\n";
    ok($trcnt->cd->title, 'Title for CD, fetched (' . $trcnt->get_column('cd') . ')');
#    print STDERR "CD title: " . $trcnt->cd->title . "\n";
}


## This is the working sql for group/prefetch combo
# my $stuff = $schema->storage->dbh_do(
#    sub {
#      my ($storage, $dbh) = @_;
#      $dbh->selectall_arrayref("SELECT me.cd, me.count, cd.cdid, cd.artist, cd.title, cd.year, cd.genreid, cd.single_track FROM (SELECT me.cd, COUNT( me.trackid ) as count FROM track me GROUP BY me.cd) AS me JOIN cd cd ON cd.cdid = me.cd");
#    },
#);

# print STDERR Data::Dumper::Dumper($stuff);

{
  my ($sql, @bind);
  $schema->storage->debugobj(DBIC::DebugObj->new(\$sql, \@bind));
  $schema->storage->debug(1);

  my $count_per_prefetched = $count_per_cd->search({}, { prefetch => 'cd' });
  is($count_per_prefetched->all, 5, 'Prefetched count with groupby');
#  print STDERR "Tracks/CDs with prefetch, count: " . $count_per_prefetched->count . "\n";

  is_same_sql_bind (
    $sql,
    \@bind,
    "SELECT me.cd, me.count, cd.cdid, cd.artist, cd.title, cd.year, cd.genreid, cd.single_track FROM (SELECT me.cd, COUNT( me.trackid ) as count FROM track me GROUP BY me.cd) AS me JOIN cd cd ON cd.cdid = me.cd",
    [ ],
  );
# }

}
