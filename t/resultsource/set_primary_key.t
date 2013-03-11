use strict;
use warnings;
use Test::More;
use Test::Exception;
use Test::Warn;

use lib 't/lib';
use DBICTest;

throws_ok {
  package Foo;
  use base 'DBIx::Class::Core';
  __PACKAGE__->table('foo');
  __PACKAGE__->set_primary_key('bar')
} qr/No such column 'bar' on source 'foo' /,
'proper exception on non-existing column as PK';

warnings_exist {
  package Foo2;
  use base 'DBIx::Class::Core';
  __PACKAGE__->table('foo');
  __PACKAGE__->add_columns(
    foo => {},
    bar => { is_nullable => 1 },
  );
  __PACKAGE__->set_primary_key(qw(foo bar))
} qr/Primary key of source 'foo' includes the column 'bar' which has its 'is_nullable' attribute set to true/,
'proper exception on is_nullable column as PK';

done_testing;
