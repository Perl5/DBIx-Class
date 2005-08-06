use Test::More;

plan tests => 22;

use lib qw(t/lib);

use_ok('DBICTest');

my @art = DBICTest::Artist->search({ }, { order_by => 'name DESC'});

cmp_ok(@art, '==', 3, "Three artists returned");

my $art = $art[0];

is($art->name, 'We Are Goth', "Correct order too");

$art->name('We Are In Rehab');

is($art->name, 'We Are In Rehab', "Accessor update ok");

is($art->get_column("name"), 'We Are In Rehab', 'And via get_column');

ok($art->update, 'Update run');

@art = DBICTest::Artist->search({ name => 'We Are In Rehab' });

cmp_ok(@art, '==', 1, "Changed artist returned by search");

cmp_ok($art[0]->artistid, '==', 3,'Correct artist too');

$art->delete;

@art = DBICTest::Artist->search({ });

cmp_ok(@art, '==', 2, 'And then there were two');

ok(!$art->in_database, "It knows it's dead");

eval { $art->delete; };

ok($@, "Can't delete twice: $@");

is($art->name, 'We Are In Rehab', 'But the object is still live');

$art->insert;

ok($art->in_database, "Re-created");

@art = DBICTest::Artist->search({ });

cmp_ok(@art, '==', 3, 'And now there are three again');

my $new = DBICTest::Artist->create({ artistid => 4 });

cmp_ok($new->artistid, '==', 4, 'Create produced record ok');

@art = DBICTest::Artist->search({ });

cmp_ok(@art, '==', 4, "Oh my god! There's four of them!");

$new->set_column('name' => 'Man With A Fork');

is($new->name, 'Man With A Fork', 'set_column ok');

$new->discard_changes;

ok(!defined $new->name, 'Discard ok');

$new->name('Man With A Spoon');

$new->update;

$new_again = DBICTest::Artist->find(4);

is($new_again->name, 'Man With A Spoon', 'Retrieved correctly');

is(DBICTest::Artist->count, 4, 'count ok');

# insert_or_update
$new = DBICTest::Track->new( {
  trackid => 100,
  cd => 1,
  position => 1,
  title => 'Insert or Update',
} );
$new->insert_or_update;
ok($new->in_database, 'insert_or_update insert ok');

# test in update mode
$new->position(5);
$new->insert_or_update;
is( DBICTest::Track->find(100)->position, 5, 'insert_or_update update ok');
