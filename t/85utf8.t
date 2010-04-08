use strict;
use warnings;

use Test::More;
use Test::Warn;
use lib qw(t/lib);
use DBICTest;

{
  package A::Comp;
  use base 'DBIx::Class';
  sub store_column { shift->next::method (@_) };
  1;
}

{
  package A::SubComp;
  use base 'A::Comp';

  1;
}

warnings_are (
  sub {
    package A::Test1;
    use base 'DBIx::Class::Core';
    __PACKAGE__->load_components(qw(Core +A::Comp Ordered UTF8Columns));
    __PACKAGE__->load_components(qw(Ordered +A::SubComp Row UTF8Columns Core));
    sub store_column { shift->next::method (@_) };
    1;
  },
  [],
  'no spurious warnings issued',
);

my $test1_mro;
my $idx = 0;
for (@{mro::get_linear_isa ('A::Test1')} ) {
  $test1_mro->{$_} = $idx++;
}

cmp_ok ($test1_mro->{'A::SubComp'}, '<', $test1_mro->{'A::Comp'}, 'mro of Test1 correct (A::SubComp before A::Comp)' );
cmp_ok ($test1_mro->{'A::Comp'}, '<', $test1_mro->{'DBIx::Class::UTF8Columns'}, 'mro of Test1 correct (A::Comp before UTF8Col)' );
cmp_ok ($test1_mro->{'DBIx::Class::UTF8Columns'}, '<', $test1_mro->{'DBIx::Class::Core'}, 'mro of Test1 correct (UTF8Col before Core)' );
cmp_ok ($test1_mro->{'DBIx::Class::Core'}, '<', $test1_mro->{'DBIx::Class::Row'}, 'mro of Test1 correct (Core before Row)' );


warnings_like (
  sub {
    package A::Test2;
    use base 'DBIx::Class::Core';
    __PACKAGE__->load_components(qw(UTF8Columns +A::Comp));
    sub store_column { shift->next::method (@_) };
    1;
  },
  [qr/Incorrect loading order of DBIx::Class::UTF8Columns.+affect other components overriding 'store_column' \(A::Comp\)/],
  'incorrect order warning issued (violator defines)',
);

warnings_like (
  sub {
    package A::Test3;
    use base 'DBIx::Class::Core';
    __PACKAGE__->load_components(qw(UTF8Columns +A::SubComp));
    sub store_column { shift->next::method (@_) };
    1;
  },
  [qr/Incorrect loading order of DBIx::Class::UTF8Columns.+affect other components overriding 'store_column' \(A::SubComp \(via A::Comp\)\)/],
  'incorrect order warning issued (violator inherits)',
);

my $schema = DBICTest->init_schema();
DBICTest::Schema::CD->load_components('UTF8Columns');
DBICTest::Schema::CD->utf8_columns('title');
Class::C3->reinitialize();

my $cd = $schema->resultset('CD')->create( { artist => 1, title => "weird\x{466}stuff", year => '2048' } );

ok( utf8::is_utf8( $cd->title ), 'got title with utf8 flag' );
ok(! utf8::is_utf8( $cd->{_column_data}{title} ), 'store title without utf8' );

ok(! utf8::is_utf8( $cd->year ), 'got year without utf8 flag' );
ok(! utf8::is_utf8( $cd->{_column_data}{year} ), 'store year without utf8' );

$cd->title('nonunicode');
ok(! utf8::is_utf8( $cd->title ), 'got title without utf8 flag' );
ok(! utf8::is_utf8( $cd->{_column_data}{title} ), 'store utf8-less chars' );


my $v_utf8 = "\x{219}";

$cd->update ({ title => $v_utf8 });
$cd->title($v_utf8);
ok( !$cd->is_column_changed('title'), 'column is not dirty after setting the same unicode value' );

$cd->update ({ title => $v_utf8 });
$cd->title('something_else');
ok( $cd->is_column_changed('title'), 'column is dirty after setting to something completely different');

TODO: {
  local $TODO = 'There is currently no way to propagate aliases to inflate_result()';
  $cd = $schema->resultset('CD')->find ({ title => $v_utf8 }, { select => 'title', as => 'name' });
  ok (utf8::is_utf8( $cd->get_column ('name') ), 'utf8 flag propagates via as');
}

done_testing;
