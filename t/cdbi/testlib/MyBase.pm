package # hide from PAUSE
    MyBase;

use strict;
use base qw(DBIx::Class::CDBICompat);

use DBI;

our $dbh;

my $err;
if (! $ENV{DBICTEST_MYSQL_DSN} ) {
  $err = 'Set $ENV{DBICTEST_MYSQL_DSN}, _USER and _PASS to run this test';
}
elsif ( ! DBIx::Class::Optional::Dependencies->req_ok_for ('test_rdbms_mysql') ) {
  $err = 'Test needs ' . DBIx::Class::Optional::Dependencies->req_missing_for ('test_rdbms_mysql')
}

if ($err) {
  my $t = eval { Test::Builder->new };
  if ($t and ! $t->current_test) {
    $t->skip_all ($err);
  }
  else {
    die "$err\n";
  }
}

my @connect = (@ENV{map { "DBICTEST_MYSQL_${_}" } qw/DSN USER PASS/}, { PrintError => 0});
$dbh = DBI->connect(@connect) or die DBI->errstr;
my @table;

END { $dbh->do("DROP TABLE $_") foreach @table }

__PACKAGE__->connection(@connect);

sub set_table {
  my $class = shift;
  $class->table($class->create_test_table);
}

sub create_test_table {
  my $self   = shift;
  my $table  = $self->next_available_table;
  my $create = sprintf "CREATE TABLE $table ( %s )", $self->create_sql;
  push @table, $table;
  $dbh->do($create);
  return $table;
}

sub next_available_table {
  my $self   = shift;
  my @tables = sort @{
    $dbh->selectcol_arrayref(
      qq{
    SHOW TABLES
  }
    )
    };
  my $table = $tables[-1] || "aaa";
  return "z$table";
}

1;
