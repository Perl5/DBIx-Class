package # hide from PAUSE
    DBICTest::Schema::Year2000CDs;

use warnings;
use strict;

use base qw/DBICTest::Schema::CD/;

# FIXME not entirely sure *why* this particular bit trips up tests
# and even more mysteriously: only a single oracle test...
# Running out of time and no local Oracle so can't investigate :/
use mro 'c3';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');
__PACKAGE__->table('year2000cds');

# need to operate on the instance for things to work
__PACKAGE__->result_source_instance->view_definition( sprintf (
  "SELECT %s FROM cd WHERE year = '2000'",
  join (', ', __PACKAGE__->columns),
));

__PACKAGE__->belongs_to( artist => 'DBICTest::Schema::Artist' );
__PACKAGE__->has_many( tracks => 'DBICTest::Schema::Track', 'cd' );

1;
