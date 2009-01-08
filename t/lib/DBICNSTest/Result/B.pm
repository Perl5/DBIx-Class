package DBICNSTest::Result::B;
use base qw/DBICNSTest::Result::A/;
__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('b');
__PACKAGE__->add_columns('b');
1;
