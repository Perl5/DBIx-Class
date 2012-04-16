use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;
use Storable qw(dclone freeze nfreeze thaw);
use Scalar::Util qw/refaddr/;

sub ref_ne {
  my ($refa, $refb) = map { refaddr $_ or die "$_ is not a reference!" } @_[0,1];
  cmp_ok (
    $refa,
      '!=',
    $refb,
    sprintf ('%s (0x%07x != 0x%07x)',
      $_[2],
      $refa,
      $refb,
    ),
  );
}

my $schema = DBICTest->init_schema;

my %stores = (
    dclone_method           => sub { return $schema->dclone($_[0]) },
    dclone_func             => sub {
      local $DBIx::Class::ResultSourceHandle::thaw_schema = $schema;
      return dclone($_[0])
    },
    "freeze/thaw_method"    => sub {
      my $ice = $schema->freeze($_[0]);
      return $schema->thaw($ice);
    },
    "nfreeze/thaw_func"      => sub {
      my $ice = freeze($_[0]);
      local $DBIx::Class::ResultSourceHandle::thaw_schema = $schema;
      return thaw($ice);
    },

    "freeze/thaw_func (cdbi legacy)" => sub {
      # this one is special-cased to leak the $schema all over
      # the same way as cdbi-compat does
      DBICTest::Artist->result_source_instance->schema($schema);
      DBICTest::CD->result_source_instance->schema($schema);

      my $fire = thaw(freeze($_[0]));

      # clean up the mess
      $_->result_source_instance->schema(undef)
        for map { $schema->class ($_) } $schema->sources;

      return $fire;
    },

);

if ($ENV{DBICTEST_MEMCACHED}) {
  if (DBIx::Class::Optional::Dependencies->req_ok_for ('test_memcached')) {
    my $memcached = Cache::Memcached->new(
      { servers => [ $ENV{DBICTEST_MEMCACHED} ] }
    );

    my $key = 'tmp_dbic_84serialize_memcached_test';

    $stores{memcached} = sub {
      $memcached->set( $key, $_[0], 60 );
      local $DBIx::Class::ResultSourceHandle::thaw_schema = $schema;
      return $memcached->get($key);
    };
  }
  else {
    SKIP: {
      skip 'Memcached tests need ' . DBIx::Class::Optional::Dependencies->req_missing_for ('test_memcached'), 1;
    }
  }
}
else {
  SKIP: {
    skip 'Set $ENV{DBICTEST_MEMCACHED} to run the memcached serialization tests', 1;
  }
}



for my $name (keys %stores) {

    my $store = $stores{$name};
    my $copy;

    my $artist = $schema->resultset('Artist')->find(1);

    lives_ok { $copy = $store->($artist) } "serialize row object lives: $name";
    ref_ne($copy, $artist, 'Simple row cloned');
    is_deeply($copy, $artist, "serialize row object works: $name");

    my $cd_rs = $artist->search_related("cds");

    # test that a live result source can be serialized as well
    is( $cd_rs->count, 3, '3 CDs in database');
    ok( $cd_rs->next, 'Advance cursor' );

    lives_ok {
      $copy = $store->($cd_rs);

      ref_ne($copy, $artist, 'Simple row cloned');

      is_deeply (
        [ $copy->all ],
        [ $cd_rs->all ],
        "serialize resultset works: $name",
      );
    } "serialize resultset lives: $name";

    # Test that an object with a related_resultset can be serialized.
    ok $artist->{related_resultsets}, 'has key: related_resultsets';

    lives_ok { $copy = $store->($artist) } "serialize row object with related_resultset lives: $name";
    for my $key (keys %$artist) {
        next if $key eq 'related_resultsets';
        next if $key eq '_inflated_column';

        ref_ne($copy->{$key}, $artist->{$key}, "Simple row internals cloned '$key'")
          if ref $artist->{$key};

        is_deeply($copy->{$key}, $artist->{$key},
                  qq[serialize with related_resultset '$key']);
    }

    lives_ok(
      sub { $copy->discard_changes }, "Discard changes works: $name"
    ) or diag $@;
    is($copy->id, $artist->id, "IDs still match ");


    # Test resultsource with cached rows
    my $query_count;
    $cd_rs = $cd_rs->search ({}, { cache => 1 });

    my $orig_debug = $schema->storage->debug;
    $schema->storage->debug(1);
    $schema->storage->debugcb(sub { $query_count++ } );

    # this will hit the database once and prime the cache
    my @cds = $cd_rs->all;

    lives_ok {
      $copy = $store->($cd_rs);
      ref_ne($copy, $cd_rs, 'Cached resultset cloned');
      is_deeply (
        [ $copy->all ],
        [ $cd_rs->all ],
        "serialize cached resultset works: $name",
      );

      is ($copy->count, $cd_rs->count, 'Cached count identical');
    } "serialize cached resultset lives: $name";

    is ($query_count, 1, 'Only one db query fired');

    $schema->storage->debug($orig_debug);
    $schema->storage->debugcb(undef);
}

# test schema-less detached thaw
{
  my $artist = $schema->resultset('Artist')->find(1);

  $artist = dclone $artist;

  is( $artist->name, 'Caterwauler McCrae', 'getting column works' );

  ok( $artist->update, 'Non-dirty update noop' );

  ok( $artist->name( 'Beeeeeeees' ), 'setting works' );

  ok( $artist->is_column_changed( 'name' ), 'Column dirtyness works' );
  ok( $artist->is_changed, 'object dirtyness works' );

  my $rs = $artist->result_source->resultset;
  $rs->set_cache([ $artist ]);

  is( $rs->count, 1, 'Synthetic resultset count works' );

  my $exc = qr/Unable to perform storage-dependent operations with a detached result source.+use \$schema->thaw/;

  throws_ok { $artist->update }
    $exc,
    'Correct exception on row op'
  ;

  throws_ok { $artist->discard_changes }
    $exc,
    'Correct exception on row op'
  ;

  throws_ok { $rs->find(1) }
    $exc,
    'Correct exception on rs op'
  ;
}

done_testing;
