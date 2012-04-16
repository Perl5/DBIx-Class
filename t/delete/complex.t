use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();
my $artist_rs = $schema->resultset ('Artist');

my $init_count = $artist_rs->count;
ok ($init_count, 'Some artists is database');

foreach my $delete_arg (
  [ { 'me.name' => 'foo' }, { 'me.name' => 'bar' } ],
  [ 'me.name' => 'foo', 'me.name' => 'bar' ],
) {
  $artist_rs->populate ([
    {
      name => 'foo',
    },
    {
      name => 'bar',
    }
  ]);

  is ($artist_rs->count, $init_count + 2, '2 Artists created');

  $artist_rs->search ({
   -and => [
    { 'me.artistid' => { '!=', undef } },
    $delete_arg,
   ],
  })->delete;

  is ($artist_rs->count, $init_count, 'Correct amount of artists deleted');
}

done_testing;

