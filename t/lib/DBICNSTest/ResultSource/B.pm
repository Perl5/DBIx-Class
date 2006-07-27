package DBICNSTest::ResultSource::B;
use base qw/DBIx::Class/;
__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('b');
__PACKAGE__->add_columns('b');
1;
