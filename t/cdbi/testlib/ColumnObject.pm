package # Hide from PAUSE
    ColumnObject;

use strict;
use warnings;

use base 'DBIC::Test::SQLite';
use Class::DBI::Column;

__PACKAGE__->set_table('column_object');

__PACKAGE__->columns( Primary => 'id' );
__PACKAGE__->columns( All => (
  'id',
  'columna',
  'columnb',
  Class::DBI::Column->new('columna' => {accessor => 'columna_as_read'}),
  Class::DBI::Column->new('columnb' => {mutator  => 'columnb_as_write'}),
));

# Disables the implicit autoinc-on-non-supplied-pk behavior
# (and the warning that goes with it)
# This is the same behavior as it was pre 0.082900
__PACKAGE__->column_info('id')->{is_auto_increment} = 0;

sub create_sql {
  return qq{
    id       INTEGER PRIMARY KEY,
    columna  VARCHAR(20),
    columnb  VARCHAR(20)
  }
}

1;
