package # hide from PAUSE 
    DBICTest;

use strict;
use warnings;
use DBICTest::Schema;

sub initialise {

  my $db_file = "t/var/DBIxClass.db";
  
  unlink($db_file) if -e $db_file;
  unlink($db_file . "-journal") if -e $db_file . "-journal";
  mkdir("t/var") unless -d "t/var";
  
  my $dsn = $ENV{"DBICTEST_DSN"} || "dbi:SQLite:${db_file}";
  my $dbuser = $ENV{"DBICTEST_DBUSER"} || '';
  my $dbpass = $ENV{"DBICTEST_DBPASS"} || '';

#  my $dsn = "dbi:SQLite:${db_file}";
  
  return DBICTest::Schema->compose_connection('DBICTest' => $dsn, $dbuser, $dbpass);
}
  
1;
