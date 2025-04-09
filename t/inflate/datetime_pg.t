use strict;
use warnings;

use Test::More;
use Test::Warn;
use DBIx::Class::Optional::Dependencies ();
use lib qw(t/lib);
use DBICTest;

plan skip_all => 'Test needs ' . DBIx::Class::Optional::Dependencies->req_missing_for ('test_dt_pg')
  unless DBIx::Class::Optional::Dependencies->req_ok_for ('test_dt_pg');

DBICTest::Schema->load_classes('EventTZPg');

my $schema = DBICTest->init_schema();

# this may generate warnings under certain CI flags, hence do it outside of
# the warnings_are below
my $dt = DateTime->new( year => 2000, time_zone => "America/Chicago" );

warnings_are {
  my $event = $schema->resultset("EventTZPg")->find(1);

  $event->update({created_on => '2009-01-15 17:00:00+00'});
  $event->discard_changes;
  isa_ok($event->created_on, "DateTime") or diag $event->created_on;
  is($event->created_on->time_zone->name, "America/Chicago", "Timezone changed");

  # Time zone difference -> -6hours
  is($event->created_on->iso8601, "2009-01-15T11:00:00", "Time with TZ correct");

  # Test behavior when DateTime has or has not fomatter
  is($event->created_on, "2009-01-15T11:00:00",      'Default DateTime does not display timezones');
  is($event->starts_at,  "2006-04-25 22:24:33-0500", 'Inflated DateTime has initialized formatter');

# test 'timestamp without time zone'
  my $dt = DateTime->from_epoch(epoch => time);
  $dt->set_nanosecond(int 500_000_000);
  $event->update({ts_without_tz => $dt});
  $event->discard_changes;
  isa_ok($event->ts_without_tz, "DateTime") or diag $event->created_on;
  is($event->ts_without_tz, $dt, 'timestamp without time zone inflation');
  is($event->ts_without_tz->microsecond, $dt->microsecond,
    'timestamp without time zone microseconds survived');
} [], 'No warnings during DT manipulations';

done_testing;
