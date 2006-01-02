package DBICTest::Schema::Producer;

use base 'DBIx::Class::Core';

__PACKAGE__->table('producer');
__PACKAGE__->add_columns(qw/producerid name/);
__PACKAGE__->set_primary_key('producerid');

1;
