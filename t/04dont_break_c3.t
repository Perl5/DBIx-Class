use warnings;
use strict;

use Test::More;
use MRO::Compat;

use lib qw(t/lib);
use DBICTest; # do not remove even though it is not used

{
  package AAA;

  use base "DBIx::Class::Core";
}

{
  package BBB;

  use base 'AAA';

  #Injecting a direct parent.
  __PACKAGE__->inject_base( __PACKAGE__, 'AAA' );
}

{
  package CCC;

  use base 'AAA';

  #Injecting an indirect parent.
  __PACKAGE__->inject_base( __PACKAGE__, 'DBIx::Class::Core' );
}

eval { mro::get_linear_isa('BBB'); };
ok (! $@, "Correctly skipped injecting a direct parent of class BBB");

eval { mro::get_linear_isa('CCC'); };
ok (! $@, "Correctly skipped injecting an indirect parent of class BBB");

use DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server;
use B;

is_deeply (
  mro::get_linear_isa('DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server'),
  [qw/
    DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server
    DBIx::Class::Storage::DBI::Sybase
    DBIx::Class::Storage::DBI::MSSQL
    DBIx::Class::Storage::DBI::UniqueIdentifier
    DBIx::Class::Storage::DBI
    DBIx::Class::Storage::DBIHacks
    DBIx::Class::Storage
    DBIx::Class
    DBIx::Class::Componentised
    Class::C3::Componentised
    Class::Accessor::Grouped
  /],
  'Correctly ordered ISA of DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server'
);

my $dialect_ref = DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server->can('sql_limit_dialect');
is (
  B::svref_2object($dialect_ref)->GV->STASH->NAME,
  'DBIx::Class::Storage::DBI::MSSQL',
  'Correct method picked'
);

done_testing;
