use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;
use PrefetchBug;

my $schema = PrefetchBug->connect( DBICTest->_database (quote_char => '"') );
ok( $schema, 'Connected to PrefetchBug schema OK' );

$schema->storage->dbh->do(<<"EOF");
CREATE TABLE prefetchbug_left (
  id INTEGER PRIMARY KEY
)
EOF

$schema->storage->dbh->do(<<"EOF");
CREATE TABLE prefetchbug_right (
  id INTEGER PRIMARY KEY,
  name TEXT,
  category TEXT,
  description TEXT,
  propagates INT,
  locked INT
)
EOF

$schema->storage->dbh->do(<<"EOF");
CREATE TABLE prefetchbug_left_right (
  left_id INTEGER REFERENCES prefetchbug_left(id),
  right_id INTEGER REFERENCES prefetchbug_right(id),
  value TEXT,
  PRIMARY KEY (left_id, right_id)
)
EOF

# Test simple has_many prefetch:

my $leftc = $schema->resultset('Left')->create({});

my $rightc = $schema->resultset('Right')->create({ id => 60, name => 'Johnny', category => 'something', description=> 'blah', propagates => 0, locked => 1 });
$rightc->create_related('prefetch_leftright', { left => $leftc, value => 'lr' });

# start with fresh whatsit
my $left = $schema->resultset('Left')->find({ id => $leftc->id });

my @left_rights = $left->search_related('prefetch_leftright', {}, { prefetch => 'right' });
ok(defined $left_rights[0]->right, 'Prefetched Right side correctly');

done_testing;
