package DBICTest;

use strict;
use warnings;
use DBICTest::Schema;

sub initialise {

  my $db_file = "t/var/DBIxClass.db";
  
  unlink($db_file) if -e $db_file;
  unlink($db_file . "-journal") if -e $db_file . "-journal";
  mkdir("t/var") unless -d "t/var";
  
  my $dsn = "dbi:SQLite:${db_file}";
  
  return DBICTest::Schema->compose_connection('DBICTest' => $dsn);
}
  
1;
