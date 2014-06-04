use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my $from_storage_ran = 0;
my $to_storage_ran = 0;
my $schema = DBICTest->init_schema( no_populate => 1 );
DBICTest::Schema::Artist->load_components(qw(FilterColumn InflateColumn));
DBICTest::Schema::Artist->filter_column(charfield => {
  filter_from_storage => sub { $from_storage_ran++; defined $_[1] ? $_[1] * 2 : undef },
  filter_to_storage   => sub { $to_storage_ran++; defined $_[1] ? $_[1] / 2 : undef },
});
Class::C3->reinitialize() if DBIx::Class::_ENV_::OLD_MRO;

my $artist = $schema->resultset('Artist')->create( { charfield => 20 } );

# this should be using the cursor directly, no inflation/processing of any sort
my ($raw_db_charfield) = $schema->resultset('Artist')
                             ->search ($artist->ident_condition)
                               ->get_column('charfield')
                                ->_resultset
                                 ->cursor
                                  ->next;

is ($raw_db_charfield, 10, 'INSERT: correctly unfiltered on insertion');

for my $reloaded (0, 1) {
  my $test = $reloaded ? 'reloaded' : 'stored';
  $artist->discard_changes if $reloaded;

  is( $artist->charfield , 20, "got $test filtered charfield" );
}

$artist->update;
$artist->discard_changes;
is( $artist->charfield , 20, "got filtered charfield" );

$artist->update ({ charfield => 40 });
($raw_db_charfield) = $schema->resultset('Artist')
                             ->search ($artist->ident_condition)
                               ->get_column('charfield')
                                ->_resultset
                                 ->cursor
                                  ->next;
is ($raw_db_charfield, 20, 'UPDATE: correctly unflitered on update');

$artist->discard_changes;
$artist->charfield(40);
ok( !$artist->is_column_changed('charfield'), 'column is not dirty after setting the same value' );

MC: {
   my $cd = $schema->resultset('CD')->create({
      artist => { charfield => 20 },
      title => 'fun time city!',
      year => 'forevertime',
   });
   ($raw_db_charfield) = $schema->resultset('Artist')
                                ->search ($cd->artist->ident_condition)
                                  ->get_column('charfield')
                                   ->_resultset
                                    ->cursor
                                     ->next;

   is $raw_db_charfield, 10, 'artist charfield gets correctly unfiltered w/ MC';
   is $cd->artist->charfield, 20, 'artist charfield gets correctly filtered w/ MC';
}

CACHE_TEST: {
  my $expected_from = $from_storage_ran;
  my $expected_to   = $to_storage_ran;

  # ensure we are creating a fresh obj
  $artist = $schema->resultset('Artist')->single($artist->ident_condition);

  is $from_storage_ran, $expected_from, 'from has not run yet';
  is $to_storage_ran, $expected_to, 'to has not run yet';

  $artist->charfield;
  cmp_ok (
    $artist->get_filtered_column('charfield'),
      '!=',
    $artist->get_column('charfield'),
    'filter/unfilter differ'
  );
  is $from_storage_ran, ++$expected_from, 'from ran once, therefor caches';
  is $to_storage_ran, $expected_to,  'to did not run';

  $artist->charfield(6);
  is $from_storage_ran, $expected_from, 'from did not run';
  is $to_storage_ran, ++$expected_to,  'to ran once';

  ok ($artist->is_column_changed ('charfield'), 'Column marked as dirty');

  $artist->charfield;
  is $from_storage_ran, $expected_from, 'from did not run';
  is $to_storage_ran, $expected_to,  'to did not run';

  $artist->update;

  $artist->set_column(charfield => 3);
  ok (! $artist->is_column_changed ('charfield'), 'Column not marked as dirty on same set_column value');
  is ($artist->charfield, '6', 'Column set properly (cache blown)');
  is $from_storage_ran, ++$expected_from, 'from ran once (set_column blew cache)';
  is $to_storage_ran, $expected_to,  'to did not run';

  $artist->charfield(6);
  ok (! $artist->is_column_changed ('charfield'), 'Column not marked as dirty on same accessor-set value');
  is ($artist->charfield, '6', 'Column set properly');
  is $from_storage_ran, $expected_from, 'from did not run';
  is $to_storage_ran, ++$expected_to,  'to did run once (call in to set_column)';

  $artist->store_column(charfield => 4);
  ok (! $artist->is_column_changed ('charfield'), 'Column not marked as dirty on differing store_column value');
  is ($artist->charfield, '8', 'Cache properly blown');
  is $from_storage_ran, ++$expected_from, 'from did not run';
  is $to_storage_ran, $expected_to,  'to did not run';

  $artist->update({ charfield => undef });
  is $from_storage_ran, $expected_from, 'from did not run';
  is $to_storage_ran, ++$expected_to,  'to did run';

  $artist->discard_changes;
  is ( $artist->get_column('charfield'), undef, 'Got back null' );
  is ( $artist->charfield, undef, 'Got back null through filter' );

  is $from_storage_ran, ++$expected_from, 'from did run';
  is $to_storage_ran, $expected_to,  'to did not run';

}

# test in-memory operations
for my $artist_maker (
  sub { $schema->resultset('Artist')->new({ charfield => 42 }) },
  sub { my $art = $schema->resultset('Artist')->new({}); $art->charfield(42); $art },
) {

  my $expected_from = $from_storage_ran;
  my $expected_to   = $to_storage_ran;

  my $artist = $artist_maker->();

  is $from_storage_ran, $expected_from, 'from has not run yet';
  is $to_storage_ran, $expected_to, 'to has not run yet';

  ok( ! $artist->has_column_loaded('artistid'), 'pk not loaded' );
  ok( $artist->has_column_loaded('charfield'), 'Filtered column marked as loaded under new' );
  is( $artist->charfield, 42, 'Proper unfiltered value' );
  is( $artist->get_column('charfield'), 21, 'Proper filtered value' );
}

# test literals
for my $v ( \ '16', \[ '?', '16' ] ) {
  my $rs = $schema->resultset('Artist');
  $rs->delete;

  my $art = $rs->new({ charfield => 10 });
  $art->charfield($v);

  is_deeply( $art->charfield, $v);
  is_deeply( $art->get_filtered_column("charfield"), $v);
  is_deeply( $art->get_column("charfield"), $v);

  $art->insert;
  $art->discard_changes;

  is ($art->get_column("charfield"), 16, "Literal inserted into database properly");
  is ($art->charfield, 32, "filtering still works");

  $art->update({ charfield => $v });

  is_deeply( $art->charfield, $v);
  is_deeply( $art->get_filtered_column("charfield"), $v);
  is_deeply( $art->get_column("charfield"), $v);

  $art->discard_changes;

  is ($art->get_column("charfield"), 16, "Literal inserted into database properly");
  is ($art->charfield, 32, "filtering still works");
}

IC_DIE: {
  throws_ok {
     DBICTest::Schema::Artist->inflate_column(charfield =>
        { inflate => sub {}, deflate => sub {} }
     );
  } qr/InflateColumn can not be used on a column with a declared FilterColumn filter/, q(Can't inflate column after filter column);

  DBICTest::Schema::Artist->inflate_column(name =>
     { inflate => sub {}, deflate => sub {} }
  );

  throws_ok {
     DBICTest::Schema::Artist->filter_column(name => {
        filter_to_storage => sub {},
        filter_from_storage => sub {}
     });
  } qr/FilterColumn can not be used on a column with a declared InflateColumn inflator/, q(Can't filter column after inflate column);
}

# test when we do not set both filter_from_storage/filter_to_storage
DBICTest::Schema::Artist->filter_column(charfield => {
  filter_to_storage => sub { $to_storage_ran++; $_[1] },
});
Class::C3->reinitialize() if DBIx::Class::_ENV_::OLD_MRO;

ASYMMETRIC_TO_TEST: {
  # initialise value
  $artist->charfield(20);
  $artist->update;

  my $expected_from = $from_storage_ran;
  my $expected_to   = $to_storage_ran;

  $artist->charfield(10);
  ok ($artist->is_column_changed ('charfield'), 'Column marked as dirty on accessor-set value');
  is ($artist->charfield, '10', 'Column set properly');
  is $from_storage_ran, $expected_from, 'from did not run';
  is $to_storage_ran, ++$expected_to,  'to did run';

  $artist->discard_changes;

  is ($artist->charfield, '20', 'Column set properly');
  is $from_storage_ran, $expected_from, 'from did not run';
  is $to_storage_ran, $expected_to,  'to did not run';
}

DBICTest::Schema::Artist->filter_column(charfield => {
  filter_from_storage => sub { $from_storage_ran++; $_[1] },
});
Class::C3->reinitialize() if DBIx::Class::_ENV_::OLD_MRO;

ASYMMETRIC_FROM_TEST: {
  # initialise value
  $artist->charfield(23);
  $artist->update;

  my $expected_from = $from_storage_ran;
  my $expected_to   = $to_storage_ran;

  $artist->charfield(13);
  ok ($artist->is_column_changed ('charfield'), 'Column marked as dirty on accessor-set value');
  is ($artist->charfield, '13', 'Column set properly');
  is $from_storage_ran, $expected_from, 'from did not run';
  is $to_storage_ran, $expected_to,  'to did not run';

  $artist->discard_changes;

  is ($artist->charfield, '23', 'Column set properly');
  is $from_storage_ran, ++$expected_from, 'from did run';
  is $to_storage_ran, $expected_to,  'to did not run';
}

throws_ok { DBICTest::Schema::Artist->filter_column( charfield => {} ) }
  qr/\QAn invocation of filter_column() must specify either a filter_from_storage or filter_to_storage/,
  'Correctly throws exception for empty attributes'
;

done_testing;
