use strict;
use warnings;

use Test::More;
use Test::Warn;
use Try::Tiny;
use lib qw(t/lib);
use DBICTest;

# so user's env doesn't screw us
delete $ENV{DBIC_DT_SEARCH_OK};

my $schema = DBICTest->init_schema();

plan skip_all => 'DT inflation tests need ' . DBIx::Class::Optional::Dependencies->req_missing_for ('test_dt_sqlite')
  unless DBIx::Class::Optional::Dependencies->req_ok_for ('test_dt_sqlite');

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
