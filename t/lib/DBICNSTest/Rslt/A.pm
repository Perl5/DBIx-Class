package DBICNSTest::Rslt::A;
use base qw/DBIx::Class::Core/;
__PACKAGE__->table('a');
__PACKAGE__->add_columns('a');

# part of a test, do not remove
$_ = 'something completely utterly bogus';

1;
