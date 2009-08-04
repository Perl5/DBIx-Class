use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

if ($] <= 5.008000) {

    eval 'use Encode; 1' or plan skip_all => 'Need Encode run this test';

} else {

    eval 'use utf8; 1' or plan skip_all => 'Need utf8 run this test';
}

plan tests => 6;

DBICTest::Schema::CD->load_components('UTF8Columns');
DBICTest::Schema::CD->utf8_columns('title');
Class::C3->reinitialize();

my $cd = $schema->resultset('CD')->create( { artist => 1, title => 'øni', year => '2048' } );
my $utf8_char = 'uniuni';


ok( _is_utf8( $cd->title ), 'got title with utf8 flag' );
ok(! _is_utf8( $cd->year ), 'got year without utf8 flag' );

_force_utf8($utf8_char);
$cd->title($utf8_char);
ok(! _is_utf8( $cd->{_column_data}{title} ), 'store utf8-less chars' );


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
  ok (_is_utf8( $cd->get_column ('name') ), 'utf8 flag propagates via as');
}


sub _force_utf8 {
  if ($] <= 5.008000) {
    Encode::_utf8_on ($_[0]);
  }
  else {
    utf8::decode ($_[0]);
  }
}

sub _is_utf8 {
  if ($] <= 5.008000) {
    return Encode::is_utf8 (shift);
  }
  else {
    return utf8::is_utf8 (shift);
  }
}
