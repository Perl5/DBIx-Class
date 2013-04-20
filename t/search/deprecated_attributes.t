use strict;
use warnings;

use Test::More;
use Test::Warn;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $cd_rs = $schema->resultset("CD")->search({ 'me.cdid' => 1 });

warnings_exist( sub {
  my $cd = $cd_rs->search( undef, {
    cols => [ { name => 'artist.name' } ],
    join => 'artist',
  })->next;

  is_deeply (
    { $cd->get_inflated_columns },
    { name => 'Caterwauler McCrae' },
    'cols attribute still works',
  );
}, qr/Resultset attribute 'cols' is deprecated/,
'deprecation warning when passing cols attribute');

warnings_exist( sub {
  my $cd = $cd_rs->search_rs( undef, {
    include_columns => [ { name => 'artist.name' } ],
    join => 'artist',
  })->next;

  is (
    $cd->get_column('name'),
    'Caterwauler McCrae',
    'include_columns attribute still works',
  );
}, qr/Resultset attribute 'include_columns' is deprecated/,
'deprecation warning when passing include_columns attribute');

done_testing;
