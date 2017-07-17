BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;

use Test::More;

use DBICTest;

my $row = DBICTest::Schema::CD->new({ title => 'foo' });

my @values = qw( foo bar baz );
for my $i ( 0 .. $#values ) {
  {
    local $TODO = 'This probably needs to always return 1, on virgin objects... same with get_dirty_columns'
      unless $i;

    ok ( $row->is_column_changed('title'), 'uninserted row properly reports "eternally changed" value' );
    is_deeply (
      { $row->get_dirty_columns },
      { title => $values[$i-1] },
      'uninserted row properly reports "eternally changed" dirty_columns()'
    );
  }

  $row->title( $values[$i] );

  ok( $row->is_column_changed('title'), 'uninserted row properly reports changed value' );
  is( $row->title, $values[$i] , 'Expected value on sourceless row' );
  for my $meth (qw( get_columns get_inflated_columns get_dirty_columns )) {
    is_deeply(
      { $row->$meth },
      { title => $values[$i] },
      "Expected '$meth' rv",
    )
  }
}

done_testing;
