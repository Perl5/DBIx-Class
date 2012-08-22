use warnings;
use strict;

use Test::More;

@INC{qw(Test::Schema::Foo Test::Schema::Baz)} = (1) x 2;

package Test::Schema::Foo;
use parent 'DBIx::Class';
__PACKAGE__->load_components(qw(Core));
__PACKAGE__->table('foo');
__PACKAGE__->add_columns(qw(id bar_id));
__PACKAGE__->set_primary_key('id');
__PACKAGE__->belongs_to(
  baz => 'Test::Schema::Baz',
  { 'foreign.id' => 'self.bar_id' }
);

package Test::Schema::Baz;
use parent 'DBIx::Class';
__PACKAGE__->load_components(qw(Core));
__PACKAGE__->table('baz');
__PACKAGE__->add_columns(qw(id quux));
__PACKAGE__->set_primary_key('id');
__PACKAGE__->has_many(
  foos => 'Test::Schema::Foo' => { 'foreign.bar_id' => 'self.id' } );

package Test::Schema;
use parent 'DBIx::Class::Schema';
__PACKAGE__->register_source(
  $_ => "Test::Schema::$_"->result_source_instance )
  for qw(Foo Baz);

package main;

my $schema = Test::Schema->connect( 'dbi:SQLite:dbname=:memory:', '', '' );
$schema->deploy;

my $foo_rs = $schema->resultset('Foo');
# create a condition that guarantees all values have 0 in them,
# which makes the inflation process skip the row because of:
#      next unless first { defined $_ } values %{$me_pref->[0]};
# all values need to be zero to ensure that the arbitrary order in
# which values() returns the results doesn't break the test
$foo_rs->create( { id => 0, baz => { id => 0, quux => 0 } } );

my $baz_rs = $schema->resultset('Baz');
ok( $baz_rs->search( {}, { prefetch => 'foos' } )->first->foos->first );

$foo_rs->delete;
$baz_rs->delete;

$foo_rs->create( { id => 1, baz => { id => 1, quux => 1 } } );
ok( $baz_rs->search( {}, { prefetch => 'foos' } )->first->foos->first );

done_testing();
