use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

$schema->resultset('Artist')->delete;
$schema->resultset('CD')->delete;

my $artist  = $schema->resultset("Artist")->create({ artistid => 21, name => 'Michael Jackson', rank => 20 });
my $cd = $artist->create_related('cds', { year => 1975, title => 'Compilation from 1975' });

$schema->is_executed_sql_bind(sub {
  my $find_cd = $artist->find_related('cds',{title => 'Compilation from 1975'});
}, [
  [
    ' SELECT me.cdid, me.artist, me.title, me.year, me.genreid, me.single_track
        FROM cd me
      WHERE me.artist = ? AND me.title = ?
      ORDER BY year ASC
    ',
    [ { dbic_colname => "me.artist", sqlt_datatype => "integer" }
      => 21 ],
    [ { dbic_colname => "me.title",  sqlt_datatype => "varchar", sqlt_size => 100 }
      => "Compilation from 1975" ],
  ]
], 'find_related only uses foreign key condition once' );

done_testing;
