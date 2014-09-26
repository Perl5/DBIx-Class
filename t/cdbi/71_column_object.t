use strict;
use warnings;

use Test::More;
use lib 't/cdbi/testlib';

# Columns in CDBI could be defined as Class::DBI::Column objects rather than
# or as well as with __PACKAGE__->columns();
BEGIN {
  eval { require Class::DBI and Class::DBI->VERSION('3.0.5') }
    or plan skip_all => 'The tested functionality is only available in Class::DBI >= 3.0.5'
}

use ColumnObject;

ok(ColumnObject->can('db_Main'), 'set_db()');
is(ColumnObject->__driver, 'SQLite', 'Driver set correctly');

ColumnObject->create({
  columna => 'Test Data',
  columnb => 'Test Data 2',
});

my $column_object = ColumnObject->retrieve(columna => 'Test Data');
$column_object->columnb_as_write('Test Data Written');
$column_object->update;
$column_object = ColumnObject->retrieve(columna => 'Test Data');

is($column_object->columna_as_read => 'Test Data', 'Read column via accessor');
is($column_object->columna         => 'Test Data', 'Real column returns right data');
is($column_object->columnb         => 'Test Data Written', 'ColumnB wrote via mutator');

done_testing;
