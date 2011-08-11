use strict;
use warnings;
use Test::More;
use Test::Exception;
use Data::Dumper::Concise;
use Try::Tiny;
use lib qw(t/lib);
use DBICTest;

my %expected = (
  'DBIx::Class::Storage::DBI'                    =>
      # no default quote_char
    {                             name_sep => '.' },

  'DBIx::Class::Storage::DBI::MSSQL'             =>
    { quote_char => [ '[', ']' ], name_sep => '.' },

  'DBIx::Class::Storage::DBI::DB2'               =>
    { quote_char => '"',          name_sep => '.' },

  'DBIx::Class::Storage::DBI::Informix'          =>
    { quote_char => '"',          name_sep => '.' },

  'DBIx::Class::Storage::DBI::InterBase'         =>
    { quote_char => '"',          name_sep => '.' },

  'DBIx::Class::Storage::DBI::mysql'             =>
    { quote_char => '`',          name_sep => '.' },

  'DBIx::Class::Storage::DBI::Pg'             =>
    { quote_char => '"',          name_sep => '.' },

  'DBIx::Class::Storage::DBI::ODBC::ACCESS'      =>
    { quote_char => [ '[', ']' ], name_sep => '.' },

# Not testing this one, it's a pain.
#  'DBIx::Class::Storage::DBI::ODBC::DB2_400_SQL' =>
#    { quote_char => '"',          name_sep => qr/must be connected/ },

  'DBIx::Class::Storage::DBI::Oracle::Generic'   =>
    { quote_char => '"',          name_sep => '.' },

  'DBIx::Class::Storage::DBI::SQLAnywhere'       =>
    { quote_char => '"',          name_sep => '.' },

  'DBIx::Class::Storage::DBI::SQLite'            =>
    { quote_char => '"',          name_sep => '.' },

  'DBIx::Class::Storage::DBI::Sybase::ASE'       =>
    { quote_char => [ '[', ']' ], name_sep => '.' },
);

for my $class (keys %expected) { SKIP: {
  eval "require ${class}"
    or skip "Skipping test of quotes for $class due to missing dependencies", 1;

  my $mapping = $expected{$class};
  my ($quote_char, $name_sep) = @$mapping{qw/quote_char name_sep/};
  my $instance = $class->new;

  my $quote_char_text = dumper($quote_char);

  if (exists $mapping->{quote_char}) {
    is_deeply $instance->sql_quote_char, $quote_char,
      "sql_quote_char for $class is $quote_char_text";
  }

  is $instance->sql_name_sep, $name_sep,
    "sql_name_sep for $class is '$name_sep'";
}}

# Try quote_names with available DBs.

# Env var to base class mapping, these are the DBs I actually have.
# the SQLITE is a fake memory dsn
local $ENV{DBICTEST_SQLITE_DSN} = 'dbi:SQLite::memory:';
my %dbs = (
  SQLITE           => 'DBIx::Class::Storage::DBI::SQLite',
  ORA              => 'DBIx::Class::Storage::DBI::Oracle::Generic',
  PG               => 'DBIx::Class::Storage::DBI::Pg',
  MYSQL            => 'DBIx::Class::Storage::DBI::mysql',
  DB2              => 'DBIx::Class::Storage::DBI::DB2',
  SYBASE           => 'DBIx::Class::Storage::DBI::Sybase::ASE',
  SQLANYWHERE      => 'DBIx::Class::Storage::DBI::SQLAnywhere',
  SQLANYWHERE_ODBC => 'DBIx::Class::Storage::DBI::SQLAnywhere',
  FIREBIRD         => 'DBIx::Class::Storage::DBI::InterBase',
  FIREBIRD_ODBC    => 'DBIx::Class::Storage::DBI::InterBase',
  INFORMIX         => 'DBIx::Class::Storage::DBI::Informix',
  MSSQL_ODBC       => 'DBIx::Class::Storage::DBI::MSSQL',
);

# Make sure oracle is tried last - some clients (e.g. 10.2) have symbol
# clashes with libssl, and will segfault everything coming after them
for my $db (sort {
    $a eq 'ORA' ? 1
  : $b eq 'ORA' ? -1
  : $a cmp $b
} keys %dbs) {
  my ($dsn, $user, $pass) = map $ENV{"DBICTEST_${db}_$_"}, qw/DSN USER PASS/;

  next unless $dsn;

  my $schema;

  try {
    $schema = DBICTest::Schema->connect($dsn, $user, $pass, {
      quote_names => 1
    });
    $schema->storage->ensure_connected;
    1;
  } || next;

  my ($exp_quote_char, $exp_name_sep) =
    @{$expected{$dbs{$db}}}{qw/quote_char name_sep/};

  my ($quote_char_text, $name_sep_text) = map { dumper($_) }
    ($exp_quote_char, $exp_name_sep);

  is_deeply $schema->storage->sql_maker->quote_char,
    $exp_quote_char,
    "$db quote_char with quote_names => 1 is $quote_char_text";


  is $schema->storage->sql_maker->name_sep,
    $exp_name_sep,
    "$db name_sep with quote_names => 1 is $name_sep_text";
}

done_testing;

sub dumper {
  my $val = shift;

  my $dd = DumperObject;
  $dd->Indent(0);
  return $dd->Values([ $val ])->Dump;
}

1;
