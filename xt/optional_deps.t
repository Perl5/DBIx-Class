use strict;
use warnings;
no warnings qw/once/;

my ($inc_before, $inc_after);
# DBIx::Class::Optional::Dependencies queries $ENV at compile time
# to build the optional requirements
BEGIN {
  $ENV{DBICTEST_PG_DSN} = '1';
  delete $ENV{DBICTEST_ORA_DSN};

  require Carp;   # Carp is not used in the test, but in OptDeps, load for proper %INC comparison

  $inc_before = [ keys %INC ];
  require DBIx::Class::Optional::Dependencies;
  $inc_after = [ keys %INC ];
}

use Test::More;
use Test::Exception;
use Scalar::Util; # load before we break require()

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
  local @INC = (sub { die('Optional Dep Test') } );

# basic test using the deploy target
  for ('deploy', ['deploy']) {

    # explicitly blow up cache
    %DBIx::Class::Optional::Dependencies::req_unavailability_cache = ();

    ok (
      ! DBIx::Class::Optional::Dependencies->req_ok_for ($_),
      'deploy() deps missing',
    );

    like (
      DBIx::Class::Optional::Dependencies->req_missing_for ($_),
      qr/
        (?: \A|\s )
        " SQL::Translator \~ \>\= [\d\.]+ "
        \s
        .*?
        \Q(see DBIx::Class::Optional::Dependencies documentation for details)\E
        \z
      /x,
      'expected missing string contents',
    );

    like (
      DBIx::Class::Optional::Dependencies->req_errorlist_for ($_)->{'SQL::Translator'},
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
      DBIx::Class::Optional::Dependencies->req_errorlist_for ($_),
      undef,
      'expected empty errorlist',
    );
  }

# test lack of deps for oracle test (envvar deleted higher up)
  is_deeply(
    DBIx::Class::Optional::Dependencies->req_list_for('test_rdbms_oracle'),
    {},
    'empty optional dependencies list for testing Oracle without ENV var',
  );

# test combination of different requirements on same module (pg's are relatively stable)
  is_deeply(
    DBIx::Class::Optional::Dependencies->req_list_for('rdbms_pg'),
    { 'DBD::Pg' => '0', },
    'optional dependencies list for using Postgres matches',
  );

  is_deeply (
    DBIx::Class::Optional::Dependencies->req_list_for([qw( rdbms_pg test_rdbms_pg )]),
    { 'DBD::Pg' => '2.009002' },
    'optional dependencies list for testing Postgres matches',
  );

  is(
    DBIx::Class::Optional::Dependencies->req_missing_for([qw( rdbms_pg test_rdbms_pg )]),
    '"DBD::Pg~>=2.009002"',
    'optional dependencies error text for testing Postgres matches',
  );

}

# test multiple times to find autovivification bugs
for (1..2) {
  throws_ok {
    DBIx::Class::Optional::Dependencies->req_list_for();
  } qr/\Qreq_list_for() expects a requirement group name/,
  "req_list_for without groupname throws exception on run $_";

  throws_ok {
    DBIx::Class::Optional::Dependencies->req_list_for('');
  } qr/\Qreq_list_for() expects a requirement group name/,
  "req_list_for with empty groupname throws exception on run $_";

  throws_ok {
    DBIx::Class::Optional::Dependencies->req_list_for('invalid_groupname');
  } qr/Requirement group 'invalid_groupname' is not defined/,
  "req_list_for with invalid groupname throws exception on run $_";
}

done_testing;
