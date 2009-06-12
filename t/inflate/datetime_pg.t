use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;

{
  local $SIG{__WARN__} = sub { warn @_ if $_[0] !~ /extra \=\> .+? has been deprecated/ };
  DBICTest::Schema->load_classes('EventTZPg');
}

eval { require DateTime::Format::Pg };
plan $@
  ? ( skip_all =>  'Need DateTime::Format::Pg for timestamp inflation tests')
  : ( tests => 3 )
;


my $schema = DBICTest->init_schema();

{
  my $event = $schema->resultset("EventTZPg")->find(1);
  $event->update({created_on => '2009-01-15 17:00:00+00'});
  $event->discard_changes;
  isa_ok($event->created_on, "DateTime") or diag $event->created_on;
  is($event->created_on->time_zone->name, "America/Chicago", "Timezone changed");
  # Time zone difference -> -6hours
  is($event->created_on->iso8601, "2009-01-15T11:00:00", "Time with TZ correct");
}
