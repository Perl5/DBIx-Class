package DBICTest::Extra::Base;
use base 'DBIx::Class';

__PACKAGE__->load_components(qw/ ResultSetManager Core /);

package DBICTest::Extra;
use base 'DBIx::Class::Schema';

__PACKAGE__->load_classes;

1;