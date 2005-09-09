package DBICTest::Schema;

use base qw/DBIx::Class::Schema/;

__PACKAGE__->load_classes(qw/
  Artist CD Track Tag LinerNotes OneKey TwoKeys FourKeys SelfRef SelfRefAlias /);

1;
