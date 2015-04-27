use DBIx::Class::Optional::Dependencies -skip_all_without => qw( ic_dt test_rdbms_sqlite );

use strict;
use warnings;

use Test::More;
use Test::Warn;
use Try::Tiny;
use lib qw(t/lib);
use DBICTest;

# Test offline parser determination (formerly t/inflate/datetime_determine_parser.t)
{
  my $schema = DBICTest->init_schema(
    no_deploy => 1, # Deploying would cause an early rebless
  );

  my $storage = $schema->storage;

  if ($ENV{DBICTEST_VIA_REPLICATED}) {
    $storage = $storage->master;
  }
  else {
    is(
      ref $storage, 'DBIx::Class::Storage::DBI',
      'Starting with generic storage'
    );
  }

  # Calling date_time_parser should cause the storage to be reblessed,
  # so that we can pick up datetime_parser_type from subclasses
  my $parser = $storage->datetime_parser();

  is($parser, 'DateTime::Format::SQLite', 'Got expected storage-set datetime_parser');
  isa_ok($storage, 'DBIx::Class::Storage::DBI::SQLite', 'storage');

  ok(! $storage->connected, 'Not yet connected');
}

# so user's env doesn't screw us
delete $ENV{DBIC_DT_SEARCH_OK};

my $schema = DBICTest->init_schema();

# inflation test
my $event = $schema->resultset("Event")->find(1);

isa_ok($event->starts_at, 'DateTime', 'DateTime returned');

# klunky, but makes older Test::More installs happy
my $starts = $event->starts_at;
is("$starts", '2006-04-25T22:24:33', 'Correct date/time');

my $dt_warn_re = qr/DateTime objects.+not supported properly/;

my $row;

{
  local $ENV{DBIC_DT_SEARCH_OK} = 1;
  local $SIG{__WARN__} = sub {
    fail('Disabled warning still issued') if $_[0] =~ $dt_warn_re;
    warn @_;
  };
  $row = $schema->resultset('Event')->search({ starts_at => $starts })->single
}

warnings_exist {
  $row = $schema->resultset('Event')->search({ starts_at => $starts })->single
} [$dt_warn_re],
  'using a DateTime object in ->search generates a warning';

{
  local $TODO = "This stuff won't work without a -dt operator of some sort"
    unless eval { require DBIx::Class::SQLMaker::DateOps };

  is(eval { $row->id }, 1, 'DT in search');

  local $ENV{DBIC_DT_SEARCH_OK} = 1;

  ok($row =
    $schema->resultset('Event')->search({ starts_at => { '>=' => $starts } })
    ->single);

  is(eval { $row->id }, 1, 'DT in search with condition');
}

# create using DateTime
my $created = $schema->resultset('Event')->create({
    starts_at => DateTime->new(year=>2006, month=>6, day=>18),
    created_on => DateTime->new(year=>2006, month=>6, day=>23)
});
my $created_start = $created->starts_at;

isa_ok($created->starts_at, 'DateTime', 'DateTime returned');
is("$created_start", '2006-06-18T00:00:00', 'Correct date/time');

## timestamp field
isa_ok($event->created_on, 'DateTime', 'DateTime returned');

## varchar fields
isa_ok($event->varchar_date, 'DateTime', 'DateTime returned');
isa_ok($event->varchar_datetime, 'DateTime', 'DateTime returned');

## skip inflation field
isnt(ref($event->skip_inflation), 'DateTime', 'No DateTime returned for skip inflation column');

# klunky, but makes older Test::More installs happy
my $createo = $event->created_on;
is("$createo", '2006-06-22T21:00:05', 'Correct date/time');

my $created_cron = $created->created_on;

isa_ok($created->created_on, 'DateTime', 'DateTime returned');
is("$created_cron", '2006-06-23T00:00:00', 'Correct date/time');

## varchar field using inflate_date => 1
my $varchar_date = $event->varchar_date;
is("$varchar_date", '2006-07-23T00:00:00', 'Correct date/time');

## varchar field using inflate_datetime => 1
my $varchar_datetime = $event->varchar_datetime;
is("$varchar_datetime", '2006-05-22T19:05:07', 'Correct date/time');

## skip inflation field
my $skip_inflation = $event->skip_inflation;
is ("$skip_inflation", '2006-04-21 18:04:06', 'Correct date/time');

# extra accessor tests with update_or_insert
{
  my $new = $schema->resultset("Track")->new( {
    trackid => 100,
    cd => 1,
    title => 'Insert or Update',
    last_updated_on => '1973-07-19 12:01:02'
  } );
  $new->update_or_insert;
  ok($new->in_storage, 'update_or_insert insert ok');

  # test in update mode
  $new->title('Insert or Update - updated');
  $new->update_or_insert;
  is( $schema->resultset("Track")->find(100)->title, 'Insert or Update - updated', 'update_or_insert update ok');

  # test get_inflated_columns with objects
  my $event = $schema->resultset('Event')->search->first;
  my %edata = $event->get_inflated_columns;
  is($edata{'id'}, $event->id, 'got id');
  isa_ok($edata{'starts_at'}, 'DateTime', 'start_at is DateTime object');
  isa_ok($edata{'created_on'}, 'DateTime', 'create_on DateTime object');
  is($edata{'starts_at'}, $event->starts_at, 'got start date');
  is($edata{'created_on'}, $event->created_on, 'got created date');

  # get_inflated_columns w/relation and accessor alias
  isa_ok($new->updated_date, 'DateTime', 'have inflated object via accessor');
  my %tdata = $new->get_inflated_columns;
  is($tdata{'trackid'}, 100, 'got id');
  isa_ok($tdata{'cd'}, 'DBICTest::CD', 'cd is CD object');
  is($tdata{'cd'}->id, 1, 'cd object is id 1');
  is(
    $tdata{'position'},
    $schema->resultset ('Track')->search ({cd => 1})->count,
    'Ordered assigned proper position',
  );
  is($tdata{'title'}, 'Insert or Update - updated');
  is($tdata{'last_updated_on'}, '1973-07-19T12:01:02');
  isa_ok($tdata{'last_updated_on'}, 'DateTime', 'inflated accessored column');
}

# create and update with literals
{
  my $d = {
    created_on => \ '2001-09-11',
    starts_at => \[ '?' => '2001-10-26' ],
  };

  my $ev = $schema->resultset('Event')->create($d);

  for my $col (qw(created_on starts_at)) {
    ok (ref $ev->$col, "literal untouched in $col");
    is_deeply( $ev->$col, $d->{$col});
    is_deeply( $ev->get_inflated_column($col), $d->{$col});
    is_deeply( $ev->get_column($col), $d->{$col});
  }

  $ev->discard_changes;

  is_deeply(
    { $ev->get_dirty_columns },
    {}
  );

  for my $col (qw(created_on starts_at)) {
    isa_ok ($ev->$col, "DateTime", "$col properly inflated on retrieve");
  }

  for my $meth (qw(set_inflated_columns set_columns)) {

    $ev->$meth({%$d});

    is_deeply(
      { $ev->get_dirty_columns },
      $d,
      "Expected dirty cols after setting literals via $meth",
    );

    $ev->update;

    for my $col (qw(created_on starts_at)) {
      ok (ref $ev->$col, "literal untouched in $col updated via $meth");
      is_deeply( $ev->$col, $d->{$col});
      is_deeply( $ev->get_inflated_column($col), $d->{$col});
      is_deeply( $ev->get_column($col), $d->{$col});
    }
  }
}

done_testing;
