use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;

plan tests => 1;

# Set up the "usual" sqlite for DBICTest
my $normal_schema = DBICTest->init_schema( sqlite_use_file => 1 );

my @connect_info = @{ $normal_schema->storage->_dbi_connect_info };

my %connect_info = (
  dsn => $connect_info[0],
  user => $connect_info[1],
  password => $connect_info[2],
  %{ $connect_info[3] },
  AutoCommit => 1,
  cursor_class => 'DBIx::Class::Storage::DBI::Cursor'
);

# Make sure we have no active connection
$normal_schema->storage->disconnect;

# Make a new clone with a new connection, using a hash reference
my $hash_schema = $normal_schema->connect(\%connect_info);

# Stolen from 60core.t - this just verifies things seem to work at all
my @art = $hash_schema->resultset("Artist")->search({ }, { order_by => 'name DESC'});
cmp_ok(@art, '==', 3, "Three artists returned");
