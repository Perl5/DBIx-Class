package # Hide from PAUSE
  DBIx::Class::SQLMaker::MSSQL;

use warnings;
use strict;

use base qw( DBIx::Class::SQLMaker );

#
# MSSQL does not support ... OVER() ... RNO limits
#
sub _rno_default_order {
  return \ '(SELECT(1))';
}

sub _datetime_now_sql { 'NOW()' }

{
  my %part_map = (
     year         => 'year',
     quarter      => 'quarter',
     month        => 'month',
     day_of_year  => 'dayofyear',
     day_of_month => 'day',
     week         => 'week',
     day_of_week  => 'weekday',
     hour         => 'hour',
     minute       => 'minute',
     second       => 'second',
     millisecond  => 'millisecond',
     nanosecond   => 'nanosecond',
  );

  my %diff_part_map = %part_map;
  $diff_part_map{day} = delete $diff_part_map{day_of_year};
  delete $diff_part_map{day_of_month};
  delete $diff_part_map{day_of_week};

  sub _datetime_sql {
    die $_[0]->_unsupported_date_extraction($_[1], 'Microsoft SQL Server')
       unless exists $part_map{$_[1]};
    "DATEPART($part_map{$_[1]}, $_[2])"
  }
  sub _datetime_diff_sql {
    die $_[0]->_unsupported_date_diff($_[1], 'Microsoft SQL Server')
       unless exists $diff_part_map{$_[1]};
    "DATEDIFF($diff_part_map{$_[1]}, $_[2], $_[3])"
  }

  sub _reorder_diff_datetime_vars {
    my ($self, $d1, $d2) = @_;

    return ($d2, $d1);
  }

  sub _datetime_add_sql {
    my ($self, $part, $amount, $date) = @_;

    die $self->_unsupported_date_adding($part, 'Microsoft SQL Server')
      unless exists $diff_part_map{$part};

    return "(DATEADD($diff_part_map{$part}, " .
      ($self->using_freetds && $amount eq '?' ? "CAST($amount AS INTEGER)" : $amount )
      . ", $date))"
  }
}

=head1 DATE FUNCTION IMPLEMENTATION

The function used to extract date information is C<DATEPART>, which supports

 year
 quarter
 month
 day_of_year
 day_of_month
 week
 day_of_week
 hour
 minute
 second
 millisecond

The function used to diff dates is C<DATEDIFF>, which supports

 year
 quarter
 month
 day
 week
 hour
 minute
 second
 millisecond

=cut

sub _where_op_ADD_DATETIME_transform_args {
   my ($self, $i, $k, $val) = @_;

   if ($i == 0 && !ref $val) {
      return $self->_convert('?'), [\'integer' => $val ]
   } else {
      return $self->next::method($i, $k, $val)
   }
}

1;
