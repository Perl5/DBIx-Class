use strict;
use warnings;
no warnings qw/once/;

my ($inc_before, $inc_after);
BEGIN {
  require Carp;   # Carp is not used in the test, but in OptDeps, load for proper %INC comparison

  $inc_before = [ keys %INC ];
  require DBIx::Class::Optional::Dependencies;
  $inc_after = [ keys %INC ];
}

use Test::More;
use Test::Exception;

# load before we break require()
use Scalar::Util();
use MRO::Compat();

ok ( (! grep { $_ =~ m|DBIx/Class| } @$inc_before ), 'Nothing DBIC related was loaded before inc-test')
  unless $ENV{PERL5OPT}; # a defined PERL5OPT may inject extra deps crashing this test

is_deeply (
  [ sort @$inc_after],
  [ sort (@$inc_before, 'DBIx/Class/Optional/Dependencies.pm') ],
  'Nothing loaded other than DBIx::Class::OptDeps',
);


# check the project-local groups for sanity
lives_ok {
  DBIx::Class::Optional::Dependencies->req_group_list
} "The entire optdep list is well formed";

is_deeply (
  [ keys %{ DBIx::Class::Optional::Dependencies->req_list_for ('deploy') } ],
  [ 'SQL::Translator' ],
  'Correct deploy() dependency list',
);

# scope to break require()
{

# make module loading impossible, regardless of actual libpath contents
  local @INC = (sub { Carp::confess('Optional Dep Test') } );

# basic test using the deploy target
  for ('deploy', ['deploy']) {

    # explicitly blow up cache
    %DBIx::Class::Optional::Dependencies::req_unavailability_cache = ();

    ok (
      ! DBIx::Class::Optional::Dependencies->req_ok_for ($_),
      'deploy() deps missing',
    );

    like (
      DBIx::Class::Optional::Dependencies->modreq_missing_for ($_),
      qr/
        \A
        " SQL::Translator \~ \>\= [\d\.]+ "
        \z
      /x,
      'expected modreq missing string contents',
    );

    like (
      DBIx::Class::Optional::Dependencies->req_missing_for ($_),
      qr/
        \A
        " SQL::Translator \~ \>\= [\d\.]+ "
        \Q (see DBIx::Class::Optional::Dependencies documentation for details)\E
        \z
      /x,
      'expected missing string contents',
    );

    like (
      DBIx::Class::Optional::Dependencies->modreq_errorlist_for ($_)->{'SQL::Translator'},
      qr/Optional Dep Test/,
      'custom exception found in errorlist',
    );

    #make it so module appears loaded
    local $INC{'SQL/Translator.pm'} = 1;
    local $SQL::Translator::VERSION = 999;

    ok (
      ! DBIx::Class::Optional::Dependencies->req_ok_for ($_),
      'deploy() deps missing cached properly from previous run',
    );

    # blow cache again
    %DBIx::Class::Optional::Dependencies::req_unavailability_cache = ();

    ok (
      DBIx::Class::Optional::Dependencies->req_ok_for ($_),
      'deploy() deps present',
    );

    is (
      DBIx::Class::Optional::Dependencies->req_missing_for ($_),
      '',
      'expected null missing string',
    );

    is_deeply (
      # use the deprecated method name
      DBIx::Class::Optional::Dependencies->req_errorlist_for ($_),
      undef,
      'expected empty errorlist',
    );
  }

# test single-db text
  local $ENV{DBICTEST_MYSQL_DSN};
  is_deeply(
    DBIx::Class::Optional::Dependencies->req_list_for('test_rdbms_mysql'),
    undef,
    'unknown optional dependencies list for testing MySQL without ENV var',
  );
  is_deeply(
    DBIx::Class::Optional::Dependencies->modreq_list_for('test_rdbms_mysql'),
    { 'DBD::mysql' => 0 },
    'correct optional module dependencies list for testing MySQL without ENV var',
  );

  local $ENV{DBICTEST_MYSQL_DSN};
  local $ENV{DBICTEST_PG_DSN};

  is_deeply(
    DBIx::Class::Optional::Dependencies->modreq_list_for('test_rdbms_pg'),
    { 'DBD::Pg' => '2.009002' },
    'optional dependencies list for testing Postgres without envvar',
  );

  is_deeply(
    DBIx::Class::Optional::Dependencies->req_list_for('test_rdbms_pg'),
    undef,
    'optional dependencies list for testing Postgres without envvar',
  );

  is_deeply(
    DBIx::Class::Optional::Dependencies->req_list_for('rdbms_pg'),
    { 'DBD::Pg' => '0', },
    'optional dependencies list for using Postgres matches',
  );

# test combination of different requirements on same module (pg's are relatively stable)
  is_deeply (
    DBIx::Class::Optional::Dependencies->req_list_for([qw( rdbms_pg test_rdbms_pg )]),
    { 'DBD::Pg' => '0' },
    'optional module dependencies list for testing Postgres matches without envvar',
  );

  is(
    DBIx::Class::Optional::Dependencies->req_missing_for([qw( rdbms_pg test_rdbms_pg )]),
    '"DBD::Pg~>=2.009002" as well as the following group(s) of environment variables: DBICTEST_PG_DSN/..._USER/..._PASS',
    'optional dependencies for testing Postgres without envvar'
  );

  is(
    DBIx::Class::Optional::Dependencies->req_missing_for([qw( test_rdbms_mysql test_rdbms_pg )]),
    'DBD::mysql "DBD::Pg~>=2.009002" as well as the following group(s) of environment variables: DBICTEST_MYSQL_DSN/..._USER/..._PASS and DBICTEST_PG_DSN/..._USER/..._PASS',
    'optional dependencies for testing Postgres+MySQL without envvars'
  );

  $ENV{DBICTEST_PG_DSN} = 'boo';
  is_deeply (
    DBIx::Class::Optional::Dependencies->modreq_list_for([qw( rdbms_pg test_rdbms_pg )]),
    { 'DBD::Pg' => '2.009002' },
    'optional module dependencies list for testing Postgres matches with envvar',
  );

  is(
    DBIx::Class::Optional::Dependencies->req_missing_for([qw( rdbms_pg test_rdbms_pg )]),
    '"DBD::Pg~>=2.009002"',
    'optional dependencies error text for testing Postgres matches with evvar',
  );

}

# test multiple times to find autovivification bugs
for my $meth (qw(req_list_for modreq_list_for)) {
  throws_ok {
    DBIx::Class::Optional::Dependencies->$meth();
  } qr/\Qreq_list_for() expects a requirement group name/,
  "$meth without groupname throws exception";

  throws_ok {
    DBIx::Class::Optional::Dependencies->$meth('');
  } qr/\Q$meth() expects a requirement group name/,
  "$meth with empty groupname throws exception";

  throws_ok {
    DBIx::Class::Optional::Dependencies->$meth('invalid_groupname');
  } qr/Requirement group 'invalid_groupname' is not defined/,
  "$meth with invalid groupname throws exception";
}

done_testing;
