# vim: filetype=perl
use strict;
use warnings;

BEGIN {
  # just in case the user env has stuff in it
  delete $ENV{JSON_ANY_ORDER};
  delete $ENV{DBICTEST_VERSION_WARNS_INDISCRIMINATELY};
}

use Test::More;
use Config;
use File::Spec;
use lib qw(t/lib);
use DBICTest;

BEGIN {
  require DBIx::Class;
  plan skip_all => 'Test needs ' .
    DBIx::Class::Optional::Dependencies->req_missing_for('test_admin_script')
      unless DBIx::Class::Optional::Dependencies->req_ok_for('test_admin_script');

  # just in case the user env has stuff in it
  delete $ENV{JSON_ANY_ORDER};
}

$ENV{PATH} = '';
$ENV{PERL5LIB} = join ($Config{path_sep}, @INC);

require JSON::Any;
my @json_backends = qw(DWIW PP JSON CPANEL XS);

# test the script is setting @INC properly
test_exec (qw|-It/lib/testinclude --schema=DBICTestAdminInc --connect=[] --insert|);
cmp_ok ( $? >> 8, '==', 70, 'Correct exit code from connecting a custom INC schema' );

# test that config works properly
{
  no warnings 'qw';
  test_exec(qw|-It/lib/testinclude --schema=DBICTestConfig --create --connect=["klaatu","barada","nikto"]|);
  cmp_ok( $? >> 8, '==', 71, 'Correct schema loaded via config' ) || exit;
}

# test that config-file works properly
test_exec(qw|-It/lib/testinclude --schema=DBICTestConfig --config=t/lib/admincfgtest.json --config-stanza=Model::Gort --deploy|);
cmp_ok ($? >> 8, '==', 71, 'Correct schema loaded via testconfig');

for my $js (@json_backends) {

    SKIP: {
        eval {JSON::Any->import ($js); 1 }
          or skip ("JSON backend $js is not available, skip testing", 1);

        local $ENV{JSON_ANY_ORDER} = $js;
        eval { test_dbicadmin () };
        diag $@ if $@;
    }
}

done_testing();

sub test_dbicadmin {
    my $schema = DBICTest->init_schema( sqlite_use_file => 1 );  # reinit a fresh db for every run

    my $employees = $schema->resultset('Employee');

    test_exec( default_args(), qw|--op=insert --set={"name":"Matt"}| );
    ok( ($employees->count()==1), "$ENV{JSON_ANY_ORDER}: insert count" );

    my $employee = $employees->find(1);
    ok( ($employee->name() eq 'Matt'), "$ENV{JSON_ANY_ORDER}: insert valid" );

    test_exec( default_args(), qw|--op=update --set={"name":"Trout"}| );
    $employee = $employees->find(1);
    ok( ($employee->name() eq 'Trout'), "$ENV{JSON_ANY_ORDER}: update" );

    test_exec( default_args(), qw|--op=insert --set={"name":"Aran"}| );

    SKIP: {
        skip ("MSWin32 doesn't support -|", 1) if $^O eq 'MSWin32';

        my ($perl) = $^X =~ /(.*)/;

        open(my $fh, "-|",  ( $perl, '-MDBICTest::RunMode', 'script/dbicadmin', default_args(), qw|--op=select --attrs={"order_by":"name"}| ) ) or die $!;
        my $data = do { local $/; <$fh> };
        close($fh);
        if (!ok( ($data=~/Aran.*Trout/s), "$ENV{JSON_ANY_ORDER}: select with attrs" )) {
          diag ("data from select is $data")
        };
    }

    test_exec( default_args(), qw|--op=delete --where={"name":"Trout"}| );
    ok( ($employees->count()==1), "$ENV{JSON_ANY_ORDER}: delete" );
}

sub default_args {
  my $dsn = JSON::Any->encode([
    'dbi:SQLite:dbname=' . DBICTest->_sqlite_dbfilename,
    '',
    '',
    { AutoCommit => 1 },
  ]);

  return (
    qw|--quiet --schema=DBICTest::Schema --class=Employee|,
    qq|--connect=$dsn|,
    qw|--force -I testincludenoniterference|,
  );
}

sub test_exec {
  my ($perl) = $^X =~ /(.*)/;

  my @args = ($perl, '-MDBICTest::RunMode', File::Spec->catfile(qw(script dbicadmin)), @_);

  if ($^O eq 'MSWin32') {
    require Win32::ShellQuote; # included in test optdeps
    @args = Win32::ShellQuote::quote_system_list(@args);
  }

  system @args;
}
