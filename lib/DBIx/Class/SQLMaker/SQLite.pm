package # Hide from PAUSE
  DBIx::Class::SQLMaker::SQLite;

use base qw( DBIx::Class::SQLMaker );

#
# SQLite does not understand SELECT ... FOR UPDATE
# Disable it here
sub _lock_select () { '' };


{
  my %part_map = (
     month               => 'm',
     day_of_month        => 'd',
     year                => 'Y',
     hour                => 'H',
     day_of_year         => 'j',
     minute              => 'M',
     seconds             => 'S',
     day_of_week         => 'w',
     week                => 'W',
     year                => 'Y',
     # should we support these or what?
     julian_day          => 'J',
     seconds_since_epoch => 's',
     fractional_seconds  => 'f',
  );

  sub _datetime_sql { "STRFTIME('%$part_map{$_[1]}', $_[2])" }
}

sub _datetime_diff_sql {
   my ($self, $part, $left, $right) = @_;
   if ($part eq 'day') {
      return "(JULIANDAY($left) - JULIANDAY($right))"
   } elsif ($part eq 'second') {
      return "(STRFTIME('%s',$left) - STRFTIME('%s',$right))"
   } else {
      die "part $part is not supported by SQLite"
   }
}

1;
