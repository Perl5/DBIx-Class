package DBICTest::Schema::Artist;

use base 'DBIx::Class::Core';

DBICTest::Schema::Artist->table('artist');
DBICTest::Schema::Artist->add_columns(qw/artistid name/);
DBICTest::Schema::Artist->set_primary_key('artistid');
DBICTest::Schema::Artist->add_relationship(
    cds => 'DBICTest::Schema::CD',
    { 'foreign.artist' => 'self.artistid' },
    { order_by => 'year' }
);
DBICTest::Schema::Artist->add_relationship(
    twokeys => 'DBICTest::Schema::TwoKeys',
    { 'foreign.artist' => 'self.artistid' }
);
DBICTest::Schema::Artist->add_relationship(
    onekeys => 'DBICTest::Schema::OneKey',
    { 'foreign.artist' => 'self.artistid' }
);

1;
