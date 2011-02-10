package # Hide from PAUSE
  DBIx::Class::SQLMaker::Pg;

use base qw( DBIx::Class::SQLMaker );
use Carp::Clan qw/^DBIx::Class|^SQL::Abstract/;

sub _datetime_now_sql { 'NOW()' }

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

  sub _datetime_sql {
    die $_[0]->_unsupported_date_extraction($_[1], 'PostgreSQL')
       unless exists $part_map{$_[1]};
    "EXTRACT($part_map{$_[1]} FROM $_[2])"
  }
  sub _datetime_diff_sql {
    die $_[0]->_unsupported_date_diff($_[1], 'PostgreSQL')
       unless exists $diff_part_map{$_[1]};
    my $field_to_extract;
    if ( $diff_part_map{$_[1]} eq 'SECOND' ) {
       $field_to_extract = "EPOCH" ;
    } else {
        $field_to_extract = $diff_part_map{$_[1]};
    }
    ## adjusting this HERE as second will be needed elsewhere
    "EXTRACT($field_to_extract FROM ($_[2]::timestamp with time zone - $_[3]::timestamp with time zone))"
  }

  sub _reorder_add_datetime_vars {
     my ($self, $amount, $date) = @_;

     return ($date, $amount);
  }

  sub _datetime_add_sql {
    my ($self, $part, $date, $amount) = @_;

    die $self->_unsupported_date_adding($part, 'PostgreSQL')
      unless exists $diff_part_map{$part};

    return "($date + $amount || ' $part_map{$part}'))"
  }
}

=head1 DATE FUNCTION IMPLEMENTATION

The function used to extract date information is C<EXTRACT>, which supports

 century
 decade
 day_of_month
 day_of_week
 day_of_year
 seconds_since_epoch
 hour
 iso_day_of_week
 iso_year
 microsecond
 millenium
 millisecond
 minute
 month
 quarter
 second
 timezone
 timezone_hour
 timezone_minute
 week
 year

The function used to diff dates is subtraction and C<EXTRACT>, which supports

 century
 decade
 day
 seconds_since_epoch
 hour
 iso_day_of_week
 iso_year
 microsecond
 millenium
 millisecond
 minute
 month
 quarter
 second
 timezone
 timezone_hour
 timezone_minute
 week
 year

=cut


1;
