use strict;
use warnings;
use Test::More;

use lib qw(t/lib);
use Data::Dumper;

plan ( ($] >= 5.009000 and $] < 5.010001)
  ? (skip_all => 'warnings::register broken under 5.10: http://rt.perl.org/rt3/Public/Bug/Display.html?id=62522')
  : (tests => 2)
);

{
  my @w; 
  local $SIG{__WARN__} = sub { push @w, @_ };

  my $code = gen_code ( suffix => 1 );
  eval "$code";

  ok ( (grep { $_ =~ /The many-to-many relationship bars is trying to create/ } @w), "Warning triggered without relevant 'no warnings'");
}

{
  my @w; 
  local $SIG{__WARN__} = sub { push @w, @_ };

  my $code = gen_code ( suffix => 2, no_warn => 1 );
  eval "$code";

diag Dumper \@w;

  ok ( (not grep { $_ =~ /The many-to-many relationship bars is trying to create/ } @w), "No warning triggered with relevant 'no warnings'");
}

sub gen_code {

  my $args = { @_ };
  my $suffix = $args->{suffix};
  my $no_warn = ( $args->{no_warn}
    ? "no warnings 'DBIx::Class::Relationship::ManyToMany';"
    : '',
  );

  return <<EOF;
use strict;
use warnings;

{
  package #
    DBICTest::Schema::Foo${suffix};
  use base 'DBIx::Class::Core';
  __PACKAGE__->table('foo');
  __PACKAGE__->add_columns(
    'fooid' => {
      data_type => 'integer',
      is_auto_increment => 1,
    },
  );
  __PACKAGE__->set_primary_key('fooid');


  __PACKAGE__->has_many('foo_to_bar' => 'DBICTest::Schema::FooToBar${suffix}' => 'bar');
  __PACKAGE__->many_to_many( foos => foo_to_bar => 'bar' );
}
{
  package #
    DBICTest::Schema::FooToBar${suffix};

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
  __PACKAGE__->belongs_to('foo' => 'DBICTest::Schema::Foo${suffix}');
  __PACKAGE__->belongs_to('bar' => 'DBICTest::Schema::Foo${suffix}');
}
{
  package #
    DBICTest::Schema::Bar${suffix};

  use base 'DBIx::Class::Core';
  __PACKAGE__->table('bar');
  __PACKAGE__->add_columns(
    'barid' => {
      data_type => 'integer',
      is_auto_increment => 1,
    },
  );

  ${no_warn}
  __PACKAGE__->set_primary_key('barid');
  __PACKAGE__->has_many('foo_to_bar' => 'DBICTest::Schema::FooToBar${suffix}' => 'foo');

  __PACKAGE__->many_to_many( bars => foo_to_bar => 'foo' );

  sub add_to_bars {}
}
EOF

}
