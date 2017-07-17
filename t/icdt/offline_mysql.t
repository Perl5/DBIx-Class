BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }
use DBIx::Class::Optional::Dependencies -skip_all_without => qw( ic_dt_mysql );

use strict;
use warnings;

use Test::More;
use Test::Exception;
use Test::Warn;

use DBICTest;
use DBICTest::Schema;
use DBIx::Class::_Util 'sigwarn_silencer';

{
  DBICTest::Schema->load_classes('EventTZ');
  local $SIG{__WARN__} = sigwarn_silencer( qr/extra \=\> .+? has been deprecated/ );
  DBICTest::Schema->load_classes('EventTZDeprecated');
}

my $schema = DBICTest->init_schema();

# Test "time_zone" parameter
foreach my $tbl (qw/EventTZ EventTZDeprecated/) {
  my $event_tz = $schema->resultset($tbl)->create({
      starts_at => DateTime->new(year=>2007, month=>12, day=>31, time_zone => "America/Chicago" ),
      created_on => DateTime->new(year=>2006, month=>1, day=>31,
          hour => 13, minute => 34, second => 56, time_zone => "America/New_York" ),
  });

  is ($event_tz->starts_at->day_name, "Montag", 'Locale de_DE loaded: day_name');
  is ($event_tz->starts_at->month_name, "Dezember", 'Locale de_DE loaded: month_name');
  is ($event_tz->created_on->day_name, "Tuesday", 'Default locale loaded: day_name');
  is ($event_tz->created_on->month_name, "January", 'Default locale loaded: month_name');

  my $starts_at = $event_tz->starts_at;
  is("$starts_at", '2007-12-31T00:00:00', 'Correct date/time using time zone');

  my $created_on = $event_tz->created_on;
  is("$created_on", '2006-01-31T12:34:56', 'Correct timestamp using time zone');
  is($event_tz->created_on->time_zone->name, "America/Chicago", "Correct time zone");

  my $loaded_event = $schema->resultset($tbl)->find( $event_tz->id );

  isa_ok($loaded_event->starts_at, 'DateTime', 'DateTime returned');
  $starts_at = $loaded_event->starts_at;
  is("$starts_at", '2007-12-31T00:00:00', 'Loaded correct date/time using time zone');
  is($starts_at->time_zone->name, 'America/Chicago', 'Correct time zone');

  isa_ok($loaded_event->created_on, 'DateTime', 'DateTime returned');
  $created_on = $loaded_event->created_on;
  is("$created_on", '2006-01-31T12:34:56', 'Loaded correct timestamp using time zone');
  is($created_on->time_zone->name, 'America/Chicago', 'Correct time zone');

  # Test floating time zone warning
  # We expect one warning
  SKIP: {
    skip "ENV{DBIC_FLOATING_TZ_OK} was set, skipping", 1 if $ENV{DBIC_FLOATING_TZ_OK};
    warnings_exist (
      sub {
        $schema->resultset($tbl)->create({
          starts_at => DateTime->new(year=>2007, month=>12, day=>31 ),
          created_on => DateTime->new(year=>2006, month=>1, day=>31, hour => 13, minute => 34, second => 56 ),
        });
      },
      qr/You're using a floating time zone, please see the documentation of DBIx::Class::InflateColumn::DateTime for an explanation/,
      'Floating time zone warning'
    );
  };

  # This should fail to set
  my $prev_str = "$created_on";
  $loaded_event->update({ created_on => '0000-00-00' });
  is("$created_on", $prev_str, "Don't update invalid dates");
}

# Test invalid DT
my $invalid = $schema->resultset('EventTZ')->create({
  starts_at  => '0000-00-00',
  created_on => DateTime->now,
});

is( $invalid->get_column('starts_at'), '0000-00-00', "Invalid date stored" );
is( $invalid->starts_at, undef, "Inflate to undef" );

$invalid->created_on('0000-00-00');
$invalid->update;

throws_ok (
  sub { $invalid->created_on },
  qr/invalid date format/i,
  "Invalid date format exception"
);

done_testing;
