use warnings;
use strict;

use Test::More;
use Test::Warn;

use lib qw(t/lib);
use DBICTest;

use DBIx::Class::_Util 'is_plain_value';

{
  package # hideee
    DBICTest::SillyInt;

  use overload
    # *DELIBERATELY* unspecified
    #fallback => 1,
    '0+' => sub { ${$_[0]} },
  ;


  package # hideee
    DBICTest::SillyInt::Subclass;

  our @ISA = 'DBICTest::SillyInt';


  package # hideee
    DBICTest::CrazyInt;

  use overload
    '0+' => sub { 666 },
    '""' => sub { 999 },
    fallback => 1,
  ;
}

# check DBI behavior when fed a stringifiable/nummifiable value
{
  my $crazynum = bless {}, 'DBICTest::CrazyInt';
  cmp_ok( $crazynum, '==', 666 );
  cmp_ok( $crazynum, 'eq', 999 );

  my $schema = DBICTest->init_schema( no_populate => 1 );
  $schema->storage->dbh_do(sub {
    $_[1]->do('INSERT INTO artist (name) VALUES (?)', {}, $crazynum );
  });

  is( $schema->resultset('Artist')->next->name, 999, 'DBI preferred stringified version' );
}

# make sure we recognize overloaded stuff properly
{
  my $num = bless( \do { my $foo = 69 }, 'DBICTest::SillyInt::Subclass' );
  ok( is_plain_value $num, 'parent-fallback-provided stringification detected' );
  is("$num", 69, 'test overloaded object stringifies, without specified fallback');
}

done_testing;
