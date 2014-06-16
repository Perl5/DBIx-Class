use strict;
use warnings;

# without this the stacktrace of $schema will be activated
BEGIN { $ENV{DBIC_TRACE} = 0 }

use Test::More;
use Test::Warn;
use Test::Exception;
use lib 't/lib';
use DBICTest;
use DBIx::Class::Carp;

{
  sub DBICTest::DBICCarp::frobnicate {
    DBICTest::DBICCarp::branch1();
    DBICTest::DBICCarp::branch2();
  }

  sub DBICTest::DBICCarp::branch1 { carp_once 'carp1' }
  sub DBICTest::DBICCarp::branch2 { carp_once 'carp2' }


  warnings_exist {
    DBICTest::DBICCarp::frobnicate();
  } [
    qr/carp1/,
    qr/carp2/,
  ], 'expected warnings from carp_once';
}

{
  {
    package DBICTest::DBICCarp::Exempt;
    use DBIx::Class::Carp;

    sub _skip_namespace_frames { qr/^DBICTest::DBICCarp::Exempt/ }

    sub thrower {
      sub {
        DBICTest->init_schema(no_deploy => 1)->storage->dbh_do(sub {
          shift->throw_exception('time to die');
        })
      }->();
    }

    sub dcaller {
      sub {
        thrower();
      }->();
    }

    sub warner {
      eval {
        sub {
          eval {
            carp ('time to warn')
          }
        }->()
      }
    }

    sub wcaller {
      warner();
    }
  }

  # the __LINE__ relationship below is important - do not reformat
  throws_ok { DBICTest::DBICCarp::Exempt::dcaller() }
    qr/\QDBICTest::DBICCarp::Exempt::thrower(): time to die at @{[ __FILE__ ]} line @{[ __LINE__ - 1 ]}\E$/,
    'Expected exception callsite and originator'
  ;

  # the __LINE__ relationship below is important - do not reformat
  warnings_like { DBICTest::DBICCarp::Exempt::wcaller() }
    qr/\QDBICTest::DBICCarp::Exempt::warner(): time to warn at @{[ __FILE__ ]} line @{[ __LINE__ - 1 ]}\E$/,
  ;
}

done_testing;
