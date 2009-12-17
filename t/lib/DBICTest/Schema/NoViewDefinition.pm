package # hide from PAUSE
    DBICTest::Schema::NoViewDefinition;

use base qw/DBICTest::BaseResult/;

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');
__PACKAGE__->table('noviewdefinition');

1;
