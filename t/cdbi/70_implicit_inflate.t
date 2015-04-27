use DBIx::Class::Optional::Dependencies -skip_all_without => qw( cdbicompat rdbms_sqlite ic_dt );

use strict;
use warnings;

# Class::DBI in its infinate wisdom allows implicit inflation
# and deflation of foriegn clas looups in has_a relationships.
# for inflate it would call ->new on the foreign_class and for
# deflate it would "" the column value and allow for overloading
# of the "" operator.

use Test::More;

use lib 't/cdbi/testlib';
use ImplicitInflate;

ok(ImplicitInflate->can('db_Main'), 'set_db()');
is(ImplicitInflate->__driver, "SQLite", 'Driver set correctly');

my $now = DateTime->now;

ImplicitInflate->create({
  update_datetime => $now,
  text            => "Test Data",
});

my $implicit_inflate = ImplicitInflate->retrieve(text => 'Test Data');

ok($implicit_inflate->update_datetime->isa('DateTime'), 'Date column inflated correctly');
is($implicit_inflate->update_datetime => $now, 'Date has correct year');

done_testing;
