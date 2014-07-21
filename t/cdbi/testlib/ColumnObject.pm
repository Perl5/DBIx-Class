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

sub create_sql {
    return qq{
        id       INTEGER PRIMARY KEY,
        columna  VARCHAR(20),
        columnb  VARCHAR(20)
    }
}

1;
