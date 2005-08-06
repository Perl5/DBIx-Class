package DBICTest::Schema::TwoKeys;

use base 'DBIx::Class::Core';

DBICTest::Schema::TwoKeys->table('twokeys');
DBICTest::Schema::TwoKeys->add_columns(qw/artist cd/);
DBICTest::Schema::TwoKeys->set_primary_key(qw/artist cd/);
DBICTest::Schema::TwoKeys->add_relationship(
    artist => 'DBICTest::Schema::Artist',
    { 'foreign.artistid' => 'self.artist' }
);
DBICTest::Schema::TwoKeys->add_relationship(
    cd => 'DBICTest::Schema::CD',
    { 'foreign.cdid' => 'self.cd' }
);

1;
