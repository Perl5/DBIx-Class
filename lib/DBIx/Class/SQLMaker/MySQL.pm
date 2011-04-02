package # Hide from PAUSE
  DBIx::Class::SQLMaker::MySQL;

use warnings;
use strict;

use base qw( DBIx::Class::SQLMaker );

#
# MySQL does not understand the standard INSERT INTO $table DEFAULT VALUES
# Adjust SQL here instead
#
sub insert {
  my $self = shift;

  if (! $_[1] or (ref $_[1] eq 'HASH' and !keys %{$_[1]} ) ) {
    my $table = $self->_quote($_[0]);
    return "INSERT INTO ${table} () VALUES ()"
  }

  return $self->next::method (@_);
}

# Allow STRAIGHT_JOIN's
sub _generate_join_clause {
    my ($self, $join_type) = @_;

    if( $join_type && $join_type =~ /^STRAIGHT\z/i ) {
        return ' STRAIGHT_JOIN '
    }

    return $self->next::method($join_type);
}

# LOCK IN SHARE MODE
my $for_syntax = {
   update => 'FOR UPDATE',
   shared => 'LOCK IN SHARE MODE'
};

sub _lock_select {
   my ($self, $type) = @_;

   my $sql = $for_syntax->{$type}
    || $self->throw_exception("Unknown SELECT .. FOR type '$type' requested");

   return " $sql";
}

sub _datetime_now_sql { 'NOW()' }
{
  my %part_map = (
    microsecond        => 'MICROSECOND',
    second             => 'SECOND',
    minute             => 'MINUTE',
    hour               => 'HOUR',
    day_of_month       => 'DAY',
    week               => 'WEEK',
    month              => 'MONTH',
    quarter            => 'QUARTER',
    year               => 'YEAR',
    second_microsecond => 'SECOND_MICROSECOND',
    minute_microsecond => 'MINUTE_MICROSECOND',
    minute_second      => 'MINUTE_SECOND',
    hour_microsecond   => 'HOUR_MICROSECOND',
    hour_second        => 'HOUR_SECOND',
    hour_minute        => 'HOUR_MINUTE',
    day_microsecond    => 'DAY_MICROSECOND',
    day_second         => 'DAY_SECOND',
    day_minute         => 'DAY_MINUTE',
    day_hour           => 'DAY_HOUR',
    year_month         => 'YEAR_MONTH',
  );

  my %diff_part_map = %part_map;
  $diff_part_map{day} = delete $diff_part_map{day_of_month};

  sub _datetime_sql {
    die $_[0]->_unsupported_date_extraction($_[1], 'MySQL')
       unless exists $part_map{$_[1]};
    "EXTRACT($part_map{$_[1]} FROM $_[2])"
  }
  sub _reorder_add_datetime_vars {
     my ($self, $amount, $date) = @_;

     return ($date, $amount);
  }
  sub _datetime_add_sql {
    die $_[0]->_unsupported_date_adding($_[1], 'MySQL')
       unless exists $diff_part_map{$_[1]};
    "DATE_ADD($_[2], INTERVAL $_[3] $diff_part_map{$_[1]})"
  }
  sub _reorder_diff_datetime_vars {
    my ($self, $d1, $d2) = @_;

    return ($d2, $d1);
  }

  sub _datetime_diff_sql {
    die $_[0]->_unsupported_date_diff($_[1], 'MySQL')
       unless exists $diff_part_map{$_[1]};
    "TIMESTAMPDIFF($diff_part_map{$_[1]}, $_[2], $_[3])"
  }
}

=head1 DATE FUNCTION IMPLEMENTATION

=head1 DATE FUNCTION IMPLEMENTATION

The function used to extract date information is C<DATEPART>, which supports

 microsecond
 second
 minute
 hour
 day_of_month
 week
 month
 quarter
 year
 second_microsecond
 minute_microsecond
 minute_second
 hour_microsecond
 hour_second
 hour_minute
 day_microsecond
 day_second
 day_minute
 day_hour
 year_month

The function used to diff dates is C<TIMESTAMPDIFF>, which supports

 microsecond
 second
 minute
 hour
 day
 week
 month
 quarter
 year
 second_microsecond
 minute_microsecond
 minute_second
 hour_microsecond
 hour_second
 hour_minute
 day_microsecond
 day_second
 day_minute
 day_hour
 year_month

=cut

1;
