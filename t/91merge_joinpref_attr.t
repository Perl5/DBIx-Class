use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

# temporary reassign for easier test debug
# not adding dependency either - just delete this
# block once everything works
use Test::Differences;
BEGIN {
  no warnings 'redefine';
  *is_deeply = \&Test::Differences::eq_or_diff;
}

my $schema = DBICTest->init_schema();
my $rs = $schema->resultset( 'CD' );

{
  my $a = { artist => { -foo => 1 } };
  my $b = { artist => { -foo => 1 } };
  my $expected = [{ artist => { -foo => 1 } }];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = [ { artist => { -foo => {} } } ];
  my $b = [ { artist => { -foo => {} } } ];
  my $expected = [ { artist => { -foo => {} } } ];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = [ { artist => { -foo => 1 } } ];
  my $b = [ { artist => { -foo => 1 } } ];
  my $expected = [ { artist => { -foo => 1 } }];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

# no conflicting options
{
  my $a = { artist => { -foo => 1 } };
  my $b = { artist => { -foo => 2 } };
  throws_ok { $rs->_merge_joinpref_attr($a, $b) }
    qr/.|Undetermined exception text/;
}

{
  my $a = [ { artist => { -foo => 1 } } ];
  my $b = [ { artist => { -foo => 2 } } ];
  throws_ok { $rs->_merge_joinpref_attr($a, $b) }
    qr/.|Undetermined exception text/;
}

{
  my $a = [ { artist => { -foo => { a => 1 } } } ];
  my $b = [ { artist => { -foo => { a => 2 } } } ];
  throws_ok { $rs->_merge_joinpref_attr($a, $b) }
    qr/.|Undetermined exception text/;
}

# also no option-bag conflicts (options can be specified
# only once due to potential problems with conflicting
# behaviors - one can only respecify the entire thing
# as in the first test above
# THIS TEST IS NOT SET IN STONE, BUT IS LIKELY CORRECT
{
  my $a = { artist => { -foo => 1 } };
  my $b = { artist => { -bar => 2 } };
  throws_ok { $rs->_merge_joinpref_attr($a, $b) }
    qr/.|Undetermined exception text/;
}

{
  my $a = 'artist';
  my $b = 'cd';
  my $expected = [ 'artist', 'cd' ];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = { artist => { -foo => 1 } };
  my $b = { cd => { -bar => 2 } };
  my $expected = [ { artist => { -foo => 1 } }, { cd => { -bar => 2 } } ];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = [ 'artist' ];
  my $b = [ 'cd' ];
  my $expected = [ 'artist', 'cd' ];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = [ 'artist', 'cd' ];
  my $b = [ 'cd' ];
  my $expected = [ 'artist', 'cd' ];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = [ 'artist', { cd => { -foo => 1 } } ];
  my $b = [ { cd => { -foo => 1 } } ];
  my $expected = [ 'artist', { cd => { -foo => 1 } } ];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = [ 'artist', 'artist' ];
  my $b = [ 'artist', 'cd' ];
  my $expected = [ 'artist', 'artist', 'cd' ];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = [ { artist => { -foo => 1 } }, { artist => { -foo => 1 } } ];
  my $b = [ { artist => { -foo => 1 } }, 'cd' ];
  my $expected = [ { artist => { -foo => 1 } }, { artist => { -foo => 1 } }, 'cd' ];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = [ 'artist', 'cd' ];
  my $b = [ 'artist', 'artist' ];
  my $expected = [ 'artist', 'cd', 'artist' ];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = [ { artist => { -foo => 1 } }, 'cd' ];
  my $b = [ { artist => { -foo => 1 } }, { artist => { -foo => 1 } } ];
  my $expected = [ { artist => { -foo => 1 } }, 'cd', { artist => { -foo => 1 } } ];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = [ 'twokeys' ];
  my $b = [ 'cds', 'cds' ];
  my $expected = [ 'twokeys', 'cds', 'cds' ];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = [ 'twokeys' ];
  my $b = [ { cds => { -bar => 1 } }, { cds => { -bar => 1 } }];
  my $expected = [ 'twokeys', { cds => { -bar => 1 } }, { cds => { -bar => 1 } }];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = [ 'artist', 'cd', { 'artist' => 'manager' } ];
  my $b = 'artist';
  my $expected = [ 'artist', 'cd', { 'artist' => 'manager' } ];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = [ { artist => { -baz => 1 } }, 'cd', { 'artist' => 'manager' } ];
  my $b = { artist => { -baz => 1 } };
  my $expected = [ { artist => { -baz => 1 } }, 'cd', { 'artist' => 'manager' } ];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = [ 'artist', 'cd', { 'artist' => 'manager' } ];
  my $b = [ 'artist', 'cd' ];
  my $expected = [ 'artist', 'cd', { 'artist' => 'manager' } ];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = [ { artist => { -biff => 1 } }, { cd => { -bong => 2 } }, { 'artist' => 'manager' } ];
  my $b = [ { artist => { -biff => 1 } }, { cd => { -bong => 2 } }];
  my $expected = [ { artist => { -biff => 1 } }, { cd => { -bong => 2 } }, { 'artist' => 'manager' }];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = [ 'artist', 'cd', { 'artist' => 'manager' } ];
  my $b = { 'artist' => 'manager' };
  my $expected = [ 'artist', 'cd', { 'artist' => [ 'manager' ] } ];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = [ 'artist', 'cd', { 'artist' => 'manager' } ];
  my $b = { 'artist' => 'agent' };
  my $expected = [ { 'artist' => 'agent' }, 'cd', { 'artist' => 'manager' } ];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = [{ artist => { -y => 'frew' } }, 'cd', { artist => { -y => 'frew', manager => 1 } } ];
  my $b = { 'artist' => { -y => 'frew', agent => 1 } };
  my $expected = [ { artist => { -y => 'frew', 'agent' => 1 } }, 'cd',  { artist => { -y => 'frew', manager => 1 } } ];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = [ 'artist', 'cd', { 'artist' => 'manager' } ];
  my $b = { 'artist' => { 'manager' => 'artist' } };
  my $expected = [ 'artist', 'cd', { 'artist' => [ { 'manager' => 'artist' } ] } ];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = [{ artist => { -yo => 1 } }, 'cd', { artist => [{ -yo => 1 }, 'manager'] } ];
  my $b = { artist => { -yo => 1, manager => { artist => { -yo => 1 } }} };
  my $expected = [{ artist => { -yo => 1 } }, 'cd', { artist => [{ -yo => 1 }, { 'manager' => { artist => { -yo => 1 } }} ] } ];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = [ 'artist', 'cd', { 'artist' => 'manager' } ];
  my $b = { 'artist' => { 'manager' => [ 'artist', 'label' ] } };
  my $expected = [ 'artist', 'cd', { 'artist' => [ { 'manager' => [ 'artist', 'label' ] } ] } ];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = [{ artist => { -x => 1 } }, 'cd', { artist => [{ -x => 1 }, 'manager' ] }];
  my $b = { artist => { -x => 1, 'manager' => [{ artist => { -x => 1 } }, 'label' ] } };
  my $expected = [{ artist => { -x => 1 } }, 'cd', { artist => { -x => 1, { 'manager' => [{ artist => { -x => 1 } }, 'label' ] } } } ];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = [ 'artist', 'cd', { 'artist' => 'manager' } ];
  my $b = { 'artist' => { 'tour_manager' => [ 'venue', 'roadie' ] } };
  my $expected = [ { 'artist' => { 'tour_manager' => [ 'venue', 'roadie' ] } }, 'cd', { 'artist' =>  'manager' } ];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = [ { artist => { -k => '' } }, 'cd', { artist => [{ -k => '' }, 'manager'] } ];
  my $b = { artist => { -k => '', tour_manager => [ 'venue', 'roadie' ] } };
  my $expected = [ { artist => { -k => '', tour_manager => [ 'venue', 'roadie' ] } }, 'cd', { artist => [{ -k => ''}, 'manager'] } ];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = [ 'artist', 'cd' ];
  my $b = { 'artist' => { 'tour_manager' => [ 'venue', 'roadie' ] } };
  my $expected = [ { 'artist' => { 'tour_manager' => [ 'venue', 'roadie' ] } }, 'cd' ];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = [{ artist => { -xyzzy => undef } }, 'cd' ];
  my $b = { artist => { -xyzzy => undef, 'tour_manager' => [ 'venue', 'roadie' ] } };
  my $expected = [ { artist => { -xyzzy => undef, 'tour_manager' => [ 'venue', 'roadie' ] } }, 'cd' ];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = [ { 'artist' => 'manager' }, 'cd' ];
  my $b = [ 'artist', { 'artist' => 'manager' } ];
  my $expected = [ { 'artist' => 'manager' }, 'cd', { 'artist' => 'manager' } ];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

{
  my $a = [{ artist => [{ -join_type => 123 }, 'manager' ] }, 'cd' ];
  my $b = [{ artist => { -join_type => 123 } }, { artist => [{ -join_type => 123 }, 'manager'] } ];
  my $expected = [ { artist => [{ -join_type => 123 }, 'manager'] }, 'cd', { artist => [{ -join_type => 123 }, 'manager'] } ];
  my $result = $rs->_merge_joinpref_attr($a, $b);
  is_deeply( $result, $expected );
}

done_testing;
