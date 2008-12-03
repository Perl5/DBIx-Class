use strict;
use warnings;
use Test::More;

use lib qw(t/lib);


our $no_warn = "";

plan tests => 2;
{
  local $@; 
  local $SIG{__WARN__} = sub { die @_ };
  eval "@{[code()]}";
  ok($@, "Warning triggered without relevant 'no warnings'");
}

{
  # Clean up the packages
  delete $INC{'DBICTest/ManyToManyWarning.pm'};
  delete $DBICTest::{"Schema::"};

  $no_warn = "no warnings 'DBIx::Class::Relationship::ManyToMany';";
  local $SIG{__WARN__} = sub { die @_ };
  eval "@{[code()]}";
  ok(!$@, "No Warning triggered with relevant 'no warnings'");
}

sub code {
my $file = << "EOF";
use strict;
use warnings;

{
  package #
    DBICTest::Schema::Foo;
  use base 'DBIx::Class::Core';
  __PACKAGE__->table('foo');
  __PACKAGE__->add_columns(
    'fooid' => {
      data_type => 'integer',
      is_auto_increment => 1,
    },
  );
  __PACKAGE__->set_primary_key('fooid');


  __PACKAGE__->has_many('foo_to_bar' => 'DBICTest::Schema::FooToBar' => 'bar');
  __PACKAGE__->many_to_many( foos => foo_to_bar => 'bar' );

}
{
  package #
    DBICTest::Schema::FooToBar;

  use base 'DBIx::Class::Core';
  __PACKAGE__->table('foo_to_bar');
  __PACKAGE__->add_columns(
    'foo' => {
      data_type => 'integer',
    },
    'bar' => {
      data_type => 'integer',
    },
  );
  __PACKAGE__->belongs_to('foo' => 'DBICTest::Schema::Foo');
  __PACKAGE__->belongs_to('bar' => 'DBICTest::Schema::Foo');
}
{
  package #
    DBICTest::Schema::Bar;
  use base 'DBIx::Class::Core';
  __PACKAGE__->table('bar');
  __PACKAGE__->add_columns(
    'barid' => {
      data_type => 'integer',
      is_auto_increment => 1,
    },
  );

  use DBIx::Class::Relationship::ManyToMany;
  $main::no_warn
  __PACKAGE__->set_primary_key('barid');
  __PACKAGE__->has_many('foo_to_bar' => 'DBICTest::Schema::FooToBar' => 'foo');
  __PACKAGE__->many_to_many( bars => foo_to_bar => 'foo' );

  sub add_to_bars {}
}
EOF
  return $file;
}
