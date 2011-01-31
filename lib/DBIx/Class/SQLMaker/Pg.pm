package # Hide from PAUSE
  DBIx::Class::SQLMaker::Pg;

use base qw( DBIx::Class::SQLMaker );
use Carp::Clan qw/^DBIx::Class|^SQL::Abstract/;
{
  my %part_map = (
     month        => 'MONTH',
     day_of_month => 'DAY',
     year         => 'YEAR',
  );

  sub _datetime_sql { "EXTRACT($part_map{$_[1]} FROM $_[2])" }
  sub _datetime_diff_sql { "EXTRACT($part_map{$_[1]} FROM ($_[2] - $_[3]))" }
}

1;
