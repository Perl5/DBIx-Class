use strict;
use warnings;  

# Stolen from 76joins.t (a good test for this purpose)

use Test::More;
use lib qw(t/lib);
use DBICTest;
use Data::Dumper;
use DBIC::SqlMakerTest;

plan tests => 1;

my $ping_count = 0;

my $schema = DBICTest->init_schema();

{
  local $SIG{__WARN__} = sub {};
  require DBIx::Class::Storage::DBI;

  my $ping = \&DBIx::Class::Storage::DBI::_ping;

  *DBIx::Class::Storage::DBI::_ping = sub {
    $ping_count++;
    goto &$ping;
  };
}

# perform some operations and make sure they don't ping

$schema->resultset('CD')->create({
  cdid => 6, artist => 3, title => 'mtfnpy', year => 2009
});

$schema->resultset('CD')->create({
  cdid => 7, artist => 3, title => 'mtfnpy2', year => 2009
});

$schema->storage->_dbh->disconnect;

$schema->resultset('CD')->create({
  cdid => 8, artist => 3, title => 'mtfnpy3', year => 2009
});

$schema->storage->_dbh->disconnect;

$schema->txn_do(sub {
 $schema->resultset('CD')->create({
   cdid => 9, artist => 3, title => 'mtfnpy4', year => 2009
 });
});

is $ping_count, 0, 'no _ping() calls';
