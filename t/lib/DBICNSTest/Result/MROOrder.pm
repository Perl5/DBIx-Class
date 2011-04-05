package DBICNSTest::Result::MROOrder;
use base qw/DBIx::Class::Core/;
use DBICNSTest::ResultSet::MROOrder;
__PACKAGE__->load_components(qw/ InflateColumn::Fargh /);
__PACKAGE__->table('mroorder');
__PACKAGE__->add_columns('mroorder');
__PACKAGE__->resultset_class ('DBICNSTest::ResultSet::MROOrder');

1;
