use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $cd = $schema->resultset("CD")->find(2);
ok $cd->liner_notes;

ok scalar(keys %{$cd->{_relationship_data}}), "_relationship_data populated";

$cd->discard_changes;
ok $cd->liner_notes, 'relationships still valid after discarding changes';

ok $cd->liner_notes->delete;
$cd->discard_changes;
ok !$cd->liner_notes, 'discard_changes resets relationship';

done_testing;
