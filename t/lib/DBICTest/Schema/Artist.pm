package DBICTest::Artist;

use base 'DBIx::Class::Core';

DBICTest::Artist->table('artist');
DBICTest::Artist->add_columns(qw/artistid name/);
DBICTest::Artist->set_primary_key('artistid');
DBICTest::Artist->add_relationship(
    cds => 'DBICTest::CD',
    { 'foreign.artist' => 'self.artistid' },
    { order_by => 'year' }
);
DBICTest::Artist->add_relationship(
    twokeys => 'DBICTest::TwoKeys',
    { 'foreign.artist' => 'self.artistid' }
);
DBICTest::Artist->add_relationship(
    onekeys => 'DBICTest::OneKey',
    { 'foreign.artist' => 'self.artistid' }
);

1;
