package # Hide from PAUSE
  DBIx::Class::SQLAHacks::MSSQL;

use warnings;
use strict;

use base qw( DBIx::Class::SQLAHacks );
use Carp::Clan qw/^DBIx::Class|^SQL::Abstract/;

# an MSSQL-specific implementation of the Row-Number-Over limiting
# technique

sub _MSRowNumberOver {
  my ($self, $sql, $order, $rows, $offset ) = @_;

  # get the order_by only
  my $order_by = $self->_order_by(
    (delete $order->{order_by}) || do {

      # no order was supplied - make something up:
      my $rsrc = $self->{_dbic_rs_attrs}{_source_handle}->resolve;
      if (my @pk = $rsrc->primary_columns) {
        \@pk;
      }
      else {
        [($rsrc->columns)[0]];
      }
    }
  );

  # whatever is left
  my $group_having = $self->_order_by($order);

  $sql = sprintf (<<'EOS', $order_by, $sql, $group_having, $offset + 1, $offset + $rows, );

SELECT * FROM (
  SELECT orig_query.*, ROW_NUMBER() OVER(%s ) AS rno__row__index FROM (%s%s) orig_query
) rno_subq WHERE rno__row__index BETWEEN %d AND %d

EOS

  $sql =~ s/\s*\n\s*/ /g;   # easier to read in the debugger
  return $sql;
}

1;
