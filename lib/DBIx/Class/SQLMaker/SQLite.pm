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
     second              => 'S',
     day_of_week         => 'w',
     week                => 'W',
     julian_day          => 'J',
     seconds_since_epoch => 's',
     fractional_seconds  => 'f',
  );

  sub _datetime_sql {
    die $_[0]->_unsupported_date_extraction($_[1], 'SQLite')
       unless exists $part_map{$_[1]};
    "STRFTIME('%$part_map{$_[1]}', $_[2])"
  }
}

sub _datetime_diff_sql {
   my ($self, $part, $left, $right) = @_;
   if ($part eq 'day') {
      return "(JULIANDAY($left) - JULIANDAY($right))"
   } elsif ($part eq 'second') {
      return "(STRFTIME('%s',$left) - STRFTIME('%s',$right))"
   } else {
      die $_[0]->_unsupported_date_diff($_[1], 'SQLite')
   }
}

{
  my %part_map = (
     day                 => 'days',
     hour                => 'hours',
     minute              => 'minutes',
     second              => 'seconds',
     month               => 'months',
     year                => 'years',
  );
   sub _datetime_add_sql {
      my ($self, $part, $date, $amount) = @_;

      die $self->_unsupported_date_adding($part, 'SQLite')
         unless exists $part_map{$part};

      return "(datetime($date, $amount || ' $part_map{$part}'))"
   }
}

sub _reorder_add_datetime_vars {
   my ($self, $amount, $date) = @_;

   return ($date, $amount);
}

sub _datetime_now_sql { "datetime('now')" }

=head1 DATE FUNCTION IMPLEMENTATION

The function used to extract date information is C<STRFTIME>, which supports

 month
 day_of_month
 year
 hour
 day_of_year
 minute
 seconds
 day_of_week
 week
 year
 julian_day
 seconds_since_epoch
 fractional_seconds

The function used to diff dates differs and only supports

 day
 second

=cut

1;
