package # hide from PAUSE 
    DBICTest;

use strict;
use warnings;
use DBICTest::Schema;
use DBICTest::Schema::Relationships;

sub init_schema {

  my $db_file = "t/var/DBIxClass.db";

  unlink($db_file) if -e $db_file;
  unlink($db_file . "-journal") if -e $db_file . "-journal";
  mkdir("t/var") unless -d "t/var";

  my $dsn = $ENV{"DBICTEST_DSN"} || "dbi:SQLite:${db_file}";
  my $dbuser = $ENV{"DBICTEST_DBUSER"} || '';
  my $dbpass = $ENV{"DBICTEST_DBPASS"} || '';

  my $schema = DBICTest::Schema->compose_connection('DBICTest' => $dsn, $dbuser, $dbpass);
  $schema->deploy();
  $schema->auto_populate();
  return $schema;

}

1;
