use strict;
use warnings;
use Test::More;

use lib qw(t/lib);


our $no_warn = "";
our $suffix = "";

plan tests => 2;
{
  local $@; 
  local $SIG{__WARN__} = sub { die @_ };
  eval "@{[code()]}";
  like($@, qr/The many-to-many relationship bars/,
       "Warning triggered without relevant 'no warnings'");
}

{

  $no_warn = "no warnings 'DBIx::Class::Relationship::ManyToMany';";
  $suffix = "2";
  local $SIG{__WARN__} = sub { die @_ };
  eval "@{[code()]}";
  unlike($@, qr/The many-to-many relationship bars.*?Bar2/s,
         "No warning triggered with relevant 'no warnings'");
}

sub code {
my $file = << "EOF";
use strict;
use warnings;

{
  package #
    DBICTest::Schema::Foo$suffix;
  use base 'DBIx::Class::Core';
  __PACKAGE__->table('foo');
  __PACKAGE__->add_columns(
    'fooid' => {
      data_type => 'integer',
      is_auto_increment => 1,
    },
  );
  __PACKAGE__->set_primary_key('fooid');


  __PACKAGE__->has_many('foo_to_bar' => 'DBICTest::Schema::FooToBar$main::suffix' => 'bar');
  __PACKAGE__->many_to_many( foos => foo_to_bar => 'bar' );

}
{
  package #
    DBICTest::Schema::FooToBar$suffix;

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
  __PACKAGE__->belongs_to('foo' => 'DBICTest::Schema::Foo$main::suffix');
  __PACKAGE__->belongs_to('bar' => 'DBICTest::Schema::Foo$main::suffix');
}
{
  package #
    DBICTest::Schema::Bar$suffix;
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
  __PACKAGE__->has_many('foo_to_bar' => 'DBICTest::Schema::FooToBar$main::suffix' => 'foo');
  __PACKAGE__->many_to_many( bars => foo_to_bar => 'foo' );

  sub add_to_bars {}
  die $main::suffix;
}
EOF
  return $file;
}
