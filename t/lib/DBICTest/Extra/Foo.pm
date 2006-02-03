package DBICTest::Extra::Foo;
use base 'DBICTest::Extra::Base';

__PACKAGE__->table('foo');

sub bar : resultset { 'good' }
