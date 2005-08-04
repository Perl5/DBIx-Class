package DBICTest::TwoKeys;

use base 'DBIx::Class::Core';

DBICTest::TwoKeys->table('twokeys');
DBICTest::TwoKeys->add_columns(qw/artist cd/);
DBICTest::TwoKeys->set_primary_key(qw/artist cd/);
DBICTest::TwoKeys->add_relationship(
    artist => 'DBICTest::Artist',
    { 'foreign.artistid' => 'self.artist' }
);
DBICTest::TwoKeys->add_relationship(
    cd => 'DBICTest::CD',
    { 'foreign.cdid' => 'self.cd' }
);

1;
