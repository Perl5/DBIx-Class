package    # hide from PAUSE
    DBICTest::Schema::StorageFlagView;

use base qw/DBICTest::BaseResult/;

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');
__PACKAGE__->table('storage_flag_pole');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(
    "SELECT id, name FROM storage_flag_pole WHERE name like 'My name%'");

1;
