use strict;
use warnings;
use Test::More;
use Test::Exception;
use Data::Dumper::Concise;
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

# SQLite first.

my $schema = DBICTest->init_schema(quote_names => 1);

is $schema->storage->sql_maker->quote_char, '"',
  q{quote_names => 1 sets correct quote_char for SQLite ('"')};

is $schema->storage->sql_maker->name_sep, '.',
  q{quote_names => 1 sets correct name_sep for SQLite (".")};

# Now the others.

# Env var to base class mapping, these are the DBs I actually have.
# -- Caelum
my %dbs = (
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

while (my ($db, $base_class) = each %dbs) {
  my ($dsn, $user, $pass) = map $ENV{"DBICTEST_${db}_$_"}, qw/DSN USER PASS/;

  next unless $dsn;

  my $schema = DBICTest::Schema->connect($dsn, $user, $pass, {
    quote_names => 1
  });

  my $expected_quote_char = $expected{$base_class}{quote_char};
  my $quote_char_text = dumper($expected_quote_char);

  is_deeply $schema->storage->sql_maker->quote_char,
    $expected_quote_char,
    "$db quote_char with quote_names => 1 is $quote_char_text";

  my $expected_name_sep = $expected{$base_class}{name_sep};

  is $schema->storage->sql_maker->name_sep,
    $expected_name_sep,
    "$db name_sep with quote_names => 1 is '$expected_name_sep'";
}

done_testing;

sub dumper {
    my $val = shift;

    my $dd = DumperObject;
    $dd->Indent(0);
    return $dd->Values([ $val ])->Dump;
}

1;
