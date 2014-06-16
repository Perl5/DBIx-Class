use strict;
use warnings;

use Test::More;
use Test::Warn;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $rs = $schema->resultset('Artist')->search({}, {
  select => 'artistid',
  prefetch => { cds => 'tracks' },
});

my $initial_artists_cnt = $rs->count;

# create one extra artist with just one cd with just one track
# and then an artist with nothing at all
# the implicit order by me.artistid will get them back in correct order
$rs->create({
  name => 'foo',
  cds => [{
    year => 2012,
    title => 'foocd',
    tracks => [{
      title => 'footrack',
    }]
  }],
});
$rs->create({ name => 'bar' });
$rs->create({ name => 'baz' });

# make sure we are reentrant, and also check with explicit order_by
for (undef, undef, 'me.artistid') {
  $rs = $rs->search({}, { order_by => $_ }) if $_;

  for (1 .. $initial_artists_cnt) {
    is ($rs->next->artistid, $_, 'Default fixture artists in order') || exit;
  }

  my $foo_artist = $rs->next;
  is ($foo_artist->cds->next->tracks->next->title, 'footrack', 'Right track');

  is (
    [$rs->cursor->next]->[0],
    $initial_artists_cnt + 3,
    'Very last artist still on the cursor'
  );

  is_deeply ([$rs->cursor->next], [], 'Nothing else left');

  is ($rs->next->artistid, $initial_artists_cnt + 2, 'Row stashed in resultset still accessible');
  is ($rs->next, undef, 'Nothing left in resultset either');

  $rs->reset;
}

$rs->next;

my @objs = $rs->all;
is (@objs, $initial_artists_cnt + 3, '->all resets everything correctly');
is ( ($rs->cursor->next)[0], 1, 'Cursor auto-rewound after all()');
is ($rs->{_stashed_rows}, undef, 'Nothing else left in $rs stash');

my $unordered_rs = $rs->search({}, { order_by => 'cds.title' });

warnings_exist {
  ok ($unordered_rs->next, 'got row 1');
} qr/performed an eager cursor slurp underneath/, 'Warned on auto-eager cursor';

is_deeply ([$unordered_rs->cursor->next], [], 'Nothing left on cursor, eager slurp');
ok ($unordered_rs->next, "got row $_")  for (2 .. $initial_artists_cnt + 3);
is ($unordered_rs->next, undef, 'End of RS reached');
is ($unordered_rs->next, undef, 'End of RS not lost');

{
  my $non_uniquely_ordered_constrained = $schema->resultset('CD')->search(
    { artist => 1 },
    { order_by => [qw( me.genreid me.title me.year )], prefetch => 'tracks' },
  );

  isa_ok ($non_uniquely_ordered_constrained->next, 'DBICTest::CD' );

  ok( defined $non_uniquely_ordered_constrained->cursor->next, 'Cursor not exhausted' );
}

done_testing;
