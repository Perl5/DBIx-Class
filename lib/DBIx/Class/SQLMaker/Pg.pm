package # Hide from PAUSE
  DBIx::Class::SQLMaker::Pg;

use base qw( DBIx::Class::SQLMaker );
use Carp::Clan qw/^DBIx::Class|^SQL::Abstract/;
{
  my %part_map = (
     century             => 'CENTURY',
     decade              => 'DECADE',
     day_of_month        => 'DAY',
     day_of_week         => 'DOW',
     day_of_year         => 'DOY',
     seconds_since_epoch => 'EPOCH',
     hour                => 'HOUR',
     iso_day_of_week     => 'ISODOW',
     iso_year            => 'ISOYEAR',
     microsecond         => 'MICROSECONDS',
     millenium           => 'MILLENIUM',
     millisecond         => 'MILLISECONDS',
     minute              => 'MINUTE',
     month               => 'MONTH',
     quarter             => 'QUARTER',
     second              => 'SECOND',
     timezone            => 'TIMEZONE',
     timezone_hour       => 'TIMEZONE_HOUR',
     timezone_minute     => 'TIMEZONE_MINUTE',
     week                => 'WEEK',
     year                => 'YEAR',
  );

  my %diff_part_map = %part_map;
  $diff_part_map{day} = delete $diff_part_map{day_of_month};

  sub _datetime_sql { "EXTRACT($part_map{$_[1]} FROM $_[2])" }
  sub _datetime_diff_sql { "EXTRACT($diff_part_map{$_[1]} FROM ($_[2] - $_[3]))" }
}

1;
