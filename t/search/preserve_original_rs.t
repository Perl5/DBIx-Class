use strict;
use warnings;

use Test::More;
use Test::Exception;

use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;
use DBIC::DebugObj;

use Storable qw/dclone/;

my $schema = DBICTest->init_schema();

# A search() with prefetch seems to pollute an already joined resultset
# in a way that offsets future joins (adapted from a test case by Debolaz)
{
  my ($cd_rs, $attrs);

  # test a real-life case - rs is obtained by an implicit m2m join
  $cd_rs = $schema->resultset ('Producer')->first->cds;
  $attrs = dclone( $cd_rs->{attrs} );

  $cd_rs->search ({})->all;
  is_deeply (dclone($cd_rs->{attrs}), $attrs, 'Resultset attributes preserved after a simple search');

  lives_ok (sub {
    $cd_rs->search ({'artist.artistid' => 1}, { prefetch => 'artist' })->all;
    is_deeply (dclone($cd_rs->{attrs}), $attrs, 'Resultset attributes preserved after search with prefetch');
  }, 'first prefetching search ok');

  lives_ok (sub {
    $cd_rs->search ({'artist.artistid' => 1}, { prefetch => 'artist' })->all;
    is_deeply (dclone($cd_rs->{attrs}), $attrs, 'Resultset attributes preserved after another search with prefetch')
  }, 'second prefetching search ok');


  # test a regular rs with an empty seen_join injected - it should still work!
  $cd_rs = $schema->resultset ('CD');
  $cd_rs->{attrs}{seen_join}  = {};
  $attrs = dclone( $cd_rs->{attrs} );

  $cd_rs->search ({})->all;
  is_deeply (dclone($cd_rs->{attrs}), $attrs, 'Resultset attributes preserved after a simple search');

  lives_ok (sub {
    $cd_rs->search ({'artist.artistid' => 1}, { prefetch => 'artist' })->all;
    is_deeply (dclone($cd_rs->{attrs}), $attrs, 'Resultset attributes preserved after search with prefetch');
  }, 'first prefetching search ok');

  lives_ok (sub {
    $cd_rs->search ({'artist.artistid' => 1}, { prefetch => 'artist' })->all;
    is_deeply (dclone($cd_rs->{attrs}), $attrs, 'Resultset attributes preserved after another search with prefetch')
  }, 'second prefetching search ok');
}

# Also test search_related, but now that we have as_query simply compare before and after
my $artist = $schema->resultset ('Artist')->first;
my %q;

$q{a2a}{rs} = $artist->search_related ('artwork_to_artist');
$q{a2a}{query} = $q{a2a}{rs}->as_query;

$q{artw}{rs} = $q{a2a}{rs}->search_related ('artwork',
  { },
  { join => ['cd', 'artwork_to_artist'] },
);
$q{artw}{query} = $q{artw}{rs}->as_query;

$q{cd}{rs} = $q{artw}{rs}->search_related ('cd', {}, { join => [ 'artist', 'tracks' ] } );
$q{cd}{query} = $q{cd}{rs}->as_query;

$q{artw_back}{rs} = $q{cd}{rs}->search_related ('artwork',
  {}, { join => { artwork_to_artist => 'artist' } }
)->search_related ('artwork_to_artist', {}, { join => 'artist' });
$q{artw_back}{query} = $q{artw_back}{rs}->as_query;

for my $s (qw/a2a artw cd artw_back/) {
  my $rs = $q{$s}{rs};

  lives_ok ( sub { $rs->first }, "first() on $s does not throw an exception" );

  lives_ok ( sub { $rs->count }, "count() on $s does not throw an exception" );

  is_same_sql_bind ($rs->as_query, $q{$s}{query}, "$s resultset unmodified (as_query matches)" );
}

# ensure nothing pollutes the attrs of an existing rs
{
  my $fresh = $schema->resultset('CD');

  isa_ok ($fresh->find(1), 'DBICTest::CD' );
  isa_ok ($fresh->single({ cdid => 1}), 'DBICTest::CD' );
  isa_ok ($fresh->search({ cdid => 1})->next, 'DBICTest::CD' );
  is ($fresh->count({ cdid => 1}), 1 );
  is ($fresh->count_rs({ cdid => 1})->next, 1 );

  ok (! exists $fresh->{cursor}, 'Still no cursor on fresh rs');
  ok (! exists $fresh->{_attrs}{_last_sqlmaker_alias_map}, 'aliasmap did not leak through' );

  my $n = $fresh->next;

  # check that we are not testing for deprecated slotnames
  ok ($fresh->{cursor}, 'Cursor at expected slot after fire');
  ok (exists $fresh->{_attrs}{_last_sqlmaker_alias_map}, 'aliasmap at expected slot after fire' );
}

done_testing;
