sub run_tests {
my $schema = shift;

plan tests => 34; 

my @art = $schema->class("Artist")->search({ }, { order_by => 'name DESC'});

cmp_ok(@art, '==', 3, "Three artists returned");

my $art = $art[0];

is($art->name, 'We Are Goth', "Correct order too");

$art->name('We Are In Rehab');

is($art->name, 'We Are In Rehab', "Accessor update ok");

is($art->get_column("name"), 'We Are In Rehab', 'And via get_column');

ok($art->update, 'Update run');

@art = $schema->class("Artist")->search({ name => 'We Are In Rehab' });

cmp_ok(@art, '==', 1, "Changed artist returned by search");

cmp_ok($art[0]->artistid, '==', 3,'Correct artist too');

$art->delete;

@art = $schema->class("Artist")->search({ });

cmp_ok(@art, '==', 2, 'And then there were two');

ok(!$art->in_storage, "It knows it's dead");

eval { $art->delete; };

ok($@, "Can't delete twice: $@");

is($art->name, 'We Are In Rehab', 'But the object is still live');

$art->insert;

ok($art->in_storage, "Re-created");

@art = $schema->class("Artist")->search({ });

cmp_ok(@art, '==', 3, 'And now there are three again');

my $new = $schema->class("Artist")->create({ artistid => 4 });

cmp_ok($new->artistid, '==', 4, 'Create produced record ok');

@art = $schema->class("Artist")->search({ });

cmp_ok(@art, '==', 4, "Oh my god! There's four of them!");

$new->set_column('name' => 'Man With A Fork');

is($new->name, 'Man With A Fork', 'set_column ok');

$new->discard_changes;

ok(!defined $new->name, 'Discard ok');

$new->name('Man With A Spoon');

$new->update;

$new_again = $schema->class("Artist")->find(4);

is($new_again->name, 'Man With A Spoon', 'Retrieved correctly');

is($new_again->ID, 'DBICTest::Artist|artistid=4', 'unique object id generated correctly');

is($schema->class("Artist")->count, 4, 'count ok');

my $cd = $schema->class("CD")->find(1);
my %cols = $cd->get_columns;

cmp_ok(keys %cols, '==', 4, 'get_columns number of columns ok');

is($cols{title}, 'Spoonful of bees', 'get_columns values ok');

%cols = ( title => 'Forkful of bees', year => 2005);
$cd->set_columns(\%cols);

is($cd->title, 'Forkful of bees', 'set_columns ok');

is($cd->year, 2005, 'set_columns ok');

$cd->discard_changes;

# check whether ResultSource->ordered_columns returns columns in order originally supplied
my @cd = $schema->source("CD")->ordered_columns;

is_deeply( \@cd, [qw/cdid artist title year/], 'ordered_columns');

$cd = $schema->class("CD")->search({ title => 'Spoonful of bees' }, { cols => ['title'] })->next;
is($cd->title, 'Spoonful of bees', 'subset of columns returned correctly');

# insert_or_update
$new = $schema->class("Track")->new( {
  trackid => 100,
  cd => 1,
  position => 1,
  title => 'Insert or Update',
} );
$new->insert_or_update;
ok($new->in_storage, 'insert_or_update insert ok');

# test in update mode
$new->position(5);
$new->insert_or_update;
is( $schema->class("Track")->find(100)->position, 5, 'insert_or_update update ok');

eval { $schema->class("Track")->load_components('DoesNotExist'); };

ok $@, $@;

is($schema->class("Artist")->field_name_for->{name}, 'artist name', 'mk_classdata usage ok');

my $search = [ { 'tags.tag' => 'Cheesy' }, { 'tags.tag' => 'Blue' } ];

my $or_rs = $schema->class("CD")->search($search, { join => 'tags',
                                                  order_by => 'cdid' });

cmp_ok($or_rs->count, '==', 5, 'Search with OR ok');

my $distinct_rs = $schema->class("CD")->search($search, { join => 'tags', distinct => 1 });

cmp_ok($distinct_rs->all, '==', 4, 'DISTINCT search with OR ok');

my $tag_rs = $schema->class('Tag')->search(
               [ { 'me.tag' => 'Cheesy' }, { 'me.tag' => 'Blue' } ]);

my $rel_rs = $tag_rs->search_related('cd');

cmp_ok($rel_rs->count, '==', 5, 'Related search ok');

cmp_ok($or_rs->next->cdid, '==', $rel_rs->next->cdid, 'Related object ok');

}

1;
