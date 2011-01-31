package # Hide from PAUSE
  DBIx::Class::SQLMaker::MSSQL;

use base qw( DBIx::Class::SQLMaker );

#
# MSSQL does not support ... OVER() ... RNO limits
#
sub _rno_default_order {
  return \ '(SELECT(1))';
}

{
  my %part_map = (
     month        => 'mm',
     day_of_month => 'dd',
     year         => 'yyyy',
  );

  my %diff_part_map = %part_map;
  $diff_part_map{day} = delete $diff_part_map{day_of_month};

  sub _datetime_sql { "DATEPART('$part_map{$_[1]}', $_[2])" }
  sub _datetime_diff_sql { "DATEDIFF('$diff_part_map{$_[1]}', $_[2], $_[3])" }
}


1;
