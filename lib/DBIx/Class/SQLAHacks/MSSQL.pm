package # Hide from PAUSE
  DBIx::Class::SQLAHacks::MSSQL;

use base qw( DBIx::Class::SQLAHacks );
use Carp::Clan qw/^DBIx::Class|^SQL::Abstract/;

sub _RowNumberOver {
  my ($self, $sql, $order, $rows, $offset ) = @_;

  $offset += 1;
  my $last = $rows + $offset - 1;
  my ( $order_by ) = $self->_order_by( $order );

  $sql = <<"SQL";
SELECT * FROM
(
   SELECT Q1.*, ROW_NUMBER() OVER( $order_by ) AS ROW_NUM FROM (
      $sql
   ) Q1
) Q2
WHERE ROW_NUM BETWEEN $offset AND $last

SQL

  return $sql;
}

1;
