use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;
use PrefetchBug;

BEGIN {
    require DBIx::Class;
    plan skip_all => 'Test needs ' .
        DBIx::Class::Optional::Dependencies->req_missing_for('deploy')
      unless DBIx::Class::Optional::Dependencies->req_ok_for('deploy');
}

  my $schema
    = PrefetchBug->connect( DBICTest->_database (quote_char => '"') );
  ok( $schema, 'Connected to PrefetchBug schema OK' );

#################### DEPLOY

  $schema->deploy( { add_drop_table => 1 } );

# Test simple has_many prefetch:

my $leftc = $schema->resultset('Left')->create({});
my $rightc = $schema->resultset('Right')->create({ id => 60, name => 'Johnny', category => 'something', description=> 'blah', propagates => 0, locked => 1 });
$rightc->create_related('prefetch_leftright', { left => $leftc, value => 'lr' });

# start with fresh whatsit
my $left = $schema->resultset('Left')->find({ id => $leftc->id });

my @left_rights = $left->search_related('prefetch_leftright', {}, { prefetch => 'right' });
ok(defined $left_rights[0]->right, 'Prefetched Right side correctly');

done_testing;
