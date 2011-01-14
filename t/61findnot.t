use strict;
use warnings;

use Test::More;
use Test::Warn;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $art = $schema->resultset("Artist")->find(4);
ok(!defined($art), 'Find on primary id: artist not found');
my @cd = $schema->resultset("CD")->find(6);
cmp_ok(@cd, '==', 1, 'Return something even in array context');
ok(@cd && !defined($cd[0]), 'Array contains an undef as only element');

$art = $schema->resultset("Artist")->find({artistid => '4'});
ok(!defined($art), 'Find on unique constraint: artist not found');
@cd = $schema->resultset("CD")->find({artist => '2', title => 'Lada-Di Lada-Da'});
cmp_ok(@cd, '==', 1, 'Return something even in array context');
ok(@cd && !defined($cd[0]), 'Array contains an undef as only element');

$art = $schema->resultset("Artist")->search({name => 'The Jesus And Mary Chain'});
isa_ok($art, 'DBIx::Class::ResultSet', 'get a DBIx::Class::ResultSet object');
my $next = $art->next;
ok(!defined($next), 'Nothing next in ResultSet');
my $cd = $schema->resultset("CD")->search({title => 'Rubbersoul'});
@cd = $cd->next;
cmp_ok(@cd, '==', 1, 'Return something even in array context');
ok(@cd && !defined($cd[0]), 'Array contains an undef as only element');

$art = $schema->resultset("Artist")->single({name => 'Bikini Bottom Boys'});
ok(!defined($art), 'Find on primary id: artist not found');
@cd = $schema->resultset("CD")->single({title => 'The Singles 1962-2006'});
cmp_ok(@cd, '==', 1, 'Return something even in array context');
ok(@cd && !defined($cd[0]), 'Array contains an undef as only element');

$art = $schema->resultset("Artist")->search({name => 'Random Girl Band'});
isa_ok($art, 'DBIx::Class::ResultSet', 'get a DBIx::Class::ResultSet object');
$next = $art->single;
ok(!defined($next), 'Nothing next in ResultSet');
$cd = $schema->resultset("CD")->search({title => 'Call of the West'});
@cd = $cd->single;
cmp_ok(@cd, '==', 1, 'Return something even in array context');
ok(@cd && !defined($cd[0]), 'Array contains an undef as only element');

$cd = $schema->resultset("CD")->first;
my $artist_rs = $schema->resultset("Artist")->search({ artistid => $cd->artist->artistid });
$art = $artist_rs->find({ name => 'some other name' }, { key => 'primary' });
ok($art, 'Artist found by key in the resultset');

# collapsing and non-collapsing are separate codepaths, thus the separate tests


$artist_rs = $schema->resultset("Artist");

warnings_exist {
  $artist_rs->find({})
} qr/\QDBIx::Class::ResultSet::find(): Query returned more than one row.  SQL that returns multiple rows is DEPRECATED for ->find and ->single/
    =>  "Non-unique find generated a cursor inexhaustion warning";

throws_ok {
  $artist_rs->find({}, { key => 'primary' })
} qr/Unable to satisfy requested constraint 'primary'/;

for (1, 0) {
  warnings_like
    sub {
      $artist_rs->find({ artistid => undef }, { key => 'primary' })
    },
    $_ ? [
      qr/undef values supplied for requested unique constraint.+almost certainly not what you wanted/,
    ] : [],
    'One warning on NULL conditions for constraint'
  ;
}


$artist_rs = $schema->resultset("Artist")->search({}, { prefetch => 'cds' });

warnings_exist {
  $artist_rs->find({})
} qr/\QDBIx::Class::ResultSet::find(): Query returned more than one row/, "Non-unique find generated a cursor inexhaustion warning";

throws_ok {
  $artist_rs->find({}, { key => 'primary' })
} qr/Unable to satisfy requested constraint 'primary'/;

done_testing;
