use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;


my $schema = DBICTest->init_schema();
my $storage = $schema->storage;

# test (re)connection
for my $disconnect (0, 1) {
  $schema->storage->_dbh->disconnect if $disconnect;
  is_deeply (
    $schema->storage->dbh_do(sub { $_[1]->selectall_arrayref('SELECT 1') }),
    [ [ 1 ] ],
    'dbh_do on fresh handle worked',
  );
}

my @args;
my $test_func = sub { @args = @_ };

$storage->dbh_do($test_func, "foo", "bar");
is_deeply (
  \@args,
  [ $storage, $storage->dbh, "foo", "bar" ],
);


my $storage_class = ref $storage;
{
  no strict 'refs';
  local *{$storage_class .'::__test_method'} = $test_func;
  $storage->dbh_do("__test_method", "baz", "buz");
}

is_deeply (
  \@args,
  [ $storage, $storage->dbh, "baz", "buz" ],
);

# test nested aliasing
my $res = 'original';
$storage->dbh_do (sub {
  shift->dbh_do(sub { $_[3] = 'changed' }, @_)
}, $res);

is ($res, 'changed', "Arguments properly aliased for dbh_do");

done_testing;
