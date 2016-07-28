package # hide from PAUSE
    MyBase;

use warnings;
use strict;

use DBI;
use DBICTest;

BEGIN {
  # offset the warning from DBIx::Class::Schema on 5.8
  # keep the ::Schema default as-is otherwise
   DBIx::Class::_ENV_::OLD_MRO
    and
  ( eval <<'EOS' or die $@ );

  sub setup_schema_instance {
    my $s = shift->next::method(@_);
    $s->schema_sanity_checker('');
    $s;
  }

  1;
EOS
}

use base qw(DBIx::Class::CDBICompat);

my @connect = (@ENV{map { "DBICTEST_MYSQL_${_}" } qw/DSN USER PASS/}, { PrintError => 0});
# this is only so we grab a lock on mysql
{
  my $x = DBICTest::Schema->connect(@connect);
}

our $dbh = DBI->connect(@connect) or die DBI->errstr;
my @table;

END {
  $dbh->do("DROP TABLE $_") for @table;
  undef $dbh;
}

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
