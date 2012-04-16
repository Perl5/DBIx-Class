use warnings;
use strict;

use Test::More;
use Test::Exception;

use lib 't/lib';
use DBICTest;

throws_ok (
  sub {
    package BuggyTable;
    use base 'DBIx::Class::Core';

    __PACKAGE__->table('buggy_table');
    __PACKAGE__->columns( qw/this doesnt work as expected/ );
  },
  qr/\bcolumns\(\) is a read-only/,
  'columns() error when apparently misused',
);

done_testing;
