package DBICNSTest::Result::MROOrder;
use base qw/DBIx::Class::Core/;
use DBICNSTest::ResultSet::MROOrder;
__PACKAGE__->table('mroorder');
__PACKAGE__->add_columns('mroorder');
__PACKAGE__->resultset_class ('DBICNSTest::ResultSet::MROOrder');
__PACKAGE__->result_source_instance->inject_resultset_components(['+A::Useless', '+A::MoarUseless']);
1;
