use strict;
use warnings;

# Do the override as early as possible so that CORE::bless doesn't get compiled away
# We will replace $bless_override only if we are in author mode
my $bless_override;
BEGIN {
  $bless_override = sub {
    CORE::bless( $_[0], (@_ > 1) ? $_[1] : caller() );
  };
  *CORE::GLOBAL::bless = sub { goto $bless_override };
}

use Test::More;
use Scalar::Util qw/refaddr reftype weaken/;
use Carp qw/longmess/;
use Try::Tiny;

use lib qw(t/lib);
use DBICTest::RunMode;

my $have_test_cycle;
BEGIN {
  require DBIx::Class::Optional::Dependencies;
  $have_test_cycle = DBIx::Class::Optional::Dependencies->req_ok_for ('test_leaks')
    and import Test::Memory::Cycle;
}

# this is what holds all weakened refs to be checked for leakage
my $weak_registry = {};

# Skip the heavy-duty leak tracing when just doing an install
unless (DBICTest::RunMode->is_plain) {

  # Some modules are known to install singletons on-load
  # Load them before we swap out $bless_override
  require DBI;
  require DBD::SQLite;
  require Errno;
  require Class::Struct;
  require FileHandle;

  no warnings qw/redefine once/;
  no strict qw/refs/;

  # redefine the bless override so that we can catch each and every object created
  $bless_override = sub {

    my $obj = CORE::bless(
      $_[0], (@_ > 1) ? $_[1] : do {
        my ($class, $fn, $line) = caller();
        fail ("bless() of $_[0] into $class without explicit class specification at $fn line $line")
          if $class =~ /^ (?: DBIx\:\:Class | DBICTest ) /x;
        $class;
      }
    );

    my $slot = (sprintf '%s=%s(0x%x)', # so we don't trigger stringification
      ref $obj,
      reftype $obj,
      refaddr $obj,
    );

    # weaken immediately to avoid weird side effects
    $weak_registry->{$slot} = { weakref => $obj, strace => longmess() };
    weaken $weak_registry->{$slot}{weakref};

    return $obj;
  };

  for my $func (qw/try catch finally/) {
    my $orig = \&{"Try::Tiny::$func"};
    *{"Try::Tiny::$func"} = sub (&;@) {

      my $slot = sprintf ('CODE(0x%x)', refaddr $_[0]);

      $weak_registry->{$slot} = { weakref => $_[0], strace => longmess() };
      weaken $weak_registry->{$slot}{weakref};

      goto $orig;
    }
  }
}

{
  require DBICTest;

  my $schema = DBICTest->init_schema;
  my $rs = $schema->resultset ('Artist');
  my $storage = $schema->storage;

  ok ($storage->connected, 'we are connected');

  my $row_obj = $rs->next;
  ok ($row_obj, 'row from db');

  my ($mc_row_obj, $pager, $pager_explicit_count) = $schema->txn_do (sub {

    my $artist = $rs->create ({
      name => 'foo artist',
      cds => [{
        title => 'foo cd',
        year => 1984,
      }],
    });

    my $pg = $rs->search({}, { rows => 1})->page(2)->pager;

    my $pg_wcount = $rs->page(4)->pager->total_entries (66);

    return ($artist, $pg, $pg_wcount);
  });

  is ($pager->next_page, 3, 'There is one more page available');

  # based on 66 per 10 pages
  is ($pager_explicit_count->last_page, 7, 'Correct last page');

  my $base_collection = {
    schema => $schema,
    storage => $storage,

    resultset => $rs,
    row_object => $row_obj,

    result_source => $rs->result_source,

    fresh_pager => $rs->page(5)->pager,
    pager => $pager,
    pager_explicit_count => $pager_explicit_count,

    sql_maker => $storage->sql_maker,
    dbh => $storage->_dbh
  };

  memory_cycle_ok ($base_collection, 'No cycles in the object collection')
    if $have_test_cycle;

  for (keys %$base_collection) {
    $weak_registry->{"basic $_"} = { weakref => $base_collection->{$_} };
    weaken $weak_registry->{"basic $_"}{weakref};
  }

}

memory_cycle_ok($weak_registry, 'No cycles in the weakened object collection')
  if $have_test_cycle;

# FIXME
# For reasons I can not yet fully understand the table() god-method (located in
# ::ResultSourceProxy::Table) attaches an actual source instance to each class
# as virtually *immortal* class-data. 
# For now just blow away these instances manually but there got to be a saner way
$_->result_source_instance(undef) for (
  'DBICTest::BaseResult',
  map { DBICTest::Schema->class ($_) } DBICTest::Schema->sources
);

# FIXME
# same problem goes for the schema - its classdata contains live result source
# objects, which to add insult to the injury are *different* instances from the
# ones we destroyed above
DBICTest::Schema->source_registrations(undef);

my $tb = Test::More->builder;
for my $slot (keys %$weak_registry) {
  # SQLT is a piece of shit, leaks all over
  next if $slot =~ /^SQL\:\:Translator/;

  ok (! defined $weak_registry->{$slot}{weakref}, "No leaks of $slot") or do {
    my $diag = '';

    $diag .= Devel::FindRef::track ($weak_registry->{$slot}{weakref}, 20) . "\n"
      if ( $ENV{TEST_VERBOSE} && try { require Devel::FindRef });

    if (my $stack = $weak_registry->{$slot}{strace}) {
      $diag .= "    Reference first seen$stack";
    }

    diag $diag if $diag;
  };
}

done_testing;
