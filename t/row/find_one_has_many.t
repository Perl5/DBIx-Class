use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;
use DBIC::DebugObj;
use DBIC::SqlMakerTest;

my $schema = DBICTest->init_schema();

$schema->resultset('Artist')->delete;
$schema->resultset('CD')->delete;

my $artist  = $schema->resultset("Artist")->create({ artistid => 21, name => 'Michael Jackson', rank => 20 });
my $cd = $artist->create_related('cds', { year => 1975, title => 'Compilation from 1975' });

my ($sql, @bind);
local $schema->storage->{debug} = 1;
local $schema->storage->{debugobj} = DBIC::DebugObj->new(\$sql, \@bind);

my $find_cd = $artist->find_related('cds',{title => 'Compilation from 1975'});

s/^'//, s/'\z// for @bind; # why does DBIC::DebugObj not do this?

is_same_sql_bind (
  $sql,
  \@bind,
  'SELECT me.cdid, me.artist, me.title, me.year, me.genreid, me.single_track FROM cd me WHERE ( ( me.artist = ? AND me.title = ? ) ) ORDER BY year ASC',
  [21, 'Compilation from 1975'],
  'find_related only uses foreign key condition once',
);

done_testing;
