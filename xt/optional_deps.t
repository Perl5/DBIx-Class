use strict;
use warnings;
no warnings qw/once/;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use Scalar::Util; # load before we break require()
use Carp ();   # Carp is not used in the test, but we want to have it loaded for proper %INC comparison

# a dummy test which lazy-loads more modules (so we can compare INC below)
ok (1);

# record contents of %INC - makes sure there are no extra deps slipping into
# Opt::Dep.
my $inc_before = [ keys %INC ];
ok ( (! grep { $_ =~ m|DBIx/Class| } @$inc_before ), 'Nothing DBIC related is yet loaded');

# DBIx::Class::Optional::Dependencies queries $ENV at compile time
# to build the optional requirements
BEGIN {
  $ENV{DBICTEST_PG_DSN} = '1';
  delete $ENV{DBICTEST_ORA_DSN};
}

use_ok 'DBIx::Class::Optional::Dependencies';

my $inc_after = [ keys %INC ];

is_deeply (
  [ sort @$inc_after],
  [ sort (@$inc_before, 'DBIx/Class/Optional/Dependencies.pm') ],
  'Nothing loaded other than DBIx::Class::OptDeps',
);

my $sqlt_dep = DBIx::Class::Optional::Dependencies->req_list_for ('deploy');
is_deeply (
  [ keys %$sqlt_dep ],
  [ 'SQL::Translator' ],
  'Correct deploy() dependency list',
);

# make module loading impossible, regardless of actual libpath contents
{
  local @INC = (sub { die('Optional Dep Test') } );

  ok (
    ! DBIx::Class::Optional::Dependencies->req_ok_for ('deploy'),
    'deploy() deps missing',
  );

  like (
    DBIx::Class::Optional::Dependencies->req_missing_for ('deploy'),
    qr/^SQL::Translator \>\= \d/,
    'expected missing string contents',
  );

  like (
    DBIx::Class::Optional::Dependencies->req_errorlist_for ('deploy')->{'SQL::Translator'},
    qr/Optional Dep Test/,
    'custom exception found in errorlist',
  );
}

#make it so module appears loaded
$INC{'SQL/Translator.pm'} = 1;
$SQL::Translator::VERSION = 999;

ok (
  ! DBIx::Class::Optional::Dependencies->req_ok_for ('deploy'),
  'deploy() deps missing cached properly',
);

#reset cache
%DBIx::Class::Optional::Dependencies::req_availability_cache = ();


ok (
  DBIx::Class::Optional::Dependencies->req_ok_for ('deploy'),
  'deploy() deps present',
);

is (
  DBIx::Class::Optional::Dependencies->req_missing_for ('deploy'),
  '',
  'expected null missing string',
);

is_deeply (
  DBIx::Class::Optional::Dependencies->req_errorlist_for ('deploy'),
  {},
  'expected empty errorlist',
);

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
  } qr/Requirement group 'invalid_groupname' does not exist/,
  "req_list_for with invalid groupname throws exception on run $_";
}

is_deeply(
  DBIx::Class::Optional::Dependencies->req_list_for('rdbms_pg'),
  {
    'DBD::Pg' => '0',
  }, 'optional dependencies for deploying to Postgres ok');

is_deeply(
  DBIx::Class::Optional::Dependencies->req_list_for('test_rdbms_pg'),
  {
    'Sys::SigAction' => '0',
    'DBD::Pg'        => '2.009002',
  }, 'optional dependencies for testing Postgres with ENV var ok');

is_deeply(
  DBIx::Class::Optional::Dependencies->req_list_for('test_rdbms_oracle'),
  {}, 'optional dependencies for testing Oracle without ENV var ok');

done_testing;
