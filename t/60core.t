use strict;
use warnings;

use Test::More;
use Test::Exception;
use Test::Warn;
use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;

my $schema = DBICTest->init_schema();

my @art = $schema->resultset("Artist")->search({ }, { order_by => 'name DESC'});

is(@art, 3, "Three artists returned");

my $art = $art[0];

is($art->name, 'We Are Goth', "Correct order too");

$art->name('We Are In Rehab');

is($art->name, 'We Are In Rehab', "Accessor update ok");

my %dirty = $art->get_dirty_columns();
is(scalar(keys(%dirty)), 1, '1 dirty column');
ok(grep($_ eq 'name', keys(%dirty)), 'name is dirty');

is($art->get_column("name"), 'We Are In Rehab', 'And via get_column');

ok($art->update, 'Update run');

my %not_dirty = $art->get_dirty_columns();
is(scalar(keys(%not_dirty)), 0, 'Nothing is dirty');

throws_ok ( sub {
  my $ret = $art->make_column_dirty('name2');
}, qr/No such column 'name2'/, 'Failed to make non-existent column dirty');

$art->make_column_dirty('name');
my %fake_dirty = $art->get_dirty_columns();
is(scalar(keys(%fake_dirty)), 1, '1 fake dirty column');
ok(grep($_ eq 'name', keys(%fake_dirty)), 'name is fake dirty');

ok($art->update, 'Update run');

my $record_jp = $schema->resultset("Artist")->search(undef, { join => 'cds' })->search(undef, { prefetch => 'cds' })->next;

ok($record_jp, "prefetch on same rel okay");

my $record_fn = $schema->resultset("Artist")->search(undef, { join => 'cds' })->search({'cds.cdid' => '1'}, {join => 'artist_undirected_maps'})->next;

ok($record_fn, "funny join is okay");

@art = $schema->resultset("Artist")->search({ name => 'We Are In Rehab' });

is(@art, 1, "Changed artist returned by search");

is($art[0]->artistid, 3,'Correct artist too');

lives_ok (sub { $art->delete }, 'Cascading delete on Ordered has_many works' );  # real test in ordered.t

@art = $schema->resultset("Artist")->search({ });

is(@art, 2, 'And then there were two');

is($art->in_storage, 0, "It knows it's dead");

lives_ok { $art->update } 'No changes so update should be OK';

dies_ok ( sub { $art->delete }, "Can't delete twice");

is($art->name, 'We Are In Rehab', 'But the object is still live');

$art->insert;

ok($art->in_storage, "Re-created");

@art = $schema->resultset("Artist")->search({ });

is(@art, 3, 'And now there are three again');

my $new = $schema->resultset("Artist")->create({ artistid => 4 });

is($new->artistid, 4, 'Create produced record ok');

@art = $schema->resultset("Artist")->search({ });

is(@art, 4, "Oh my god! There's four of them!");

$new->set_column('name' => 'Man With A Fork');

is($new->name, 'Man With A Fork', 'set_column ok');

$new->discard_changes;

ok(!defined $new->name, 'Discard ok');

$new->name('Man With A Spoon');

$new->update;

my $new_again = $schema->resultset("Artist")->find(4);

is($new_again->name, 'Man With A Spoon', 'Retrieved correctly');

is($new_again->ID, 'DBICTest::Artist|artist|artistid=4', 'unique object id generated correctly');

# test that store_column is called once for create() for non sequence columns
{
  ok(my $artist = $schema->resultset('Artist')->create({name => 'store_column test'}));
  is($artist->name, 'X store_column test'); # used to be 'X X store...'

  # call store_column even though the column doesn't seem to be dirty
  $artist->name($artist->name);
  is($artist->name, 'X X store_column test');
  ok($artist->is_column_changed('name'), 'changed column marked as dirty');

  $artist->delete;
}

# deprecation of rolled-out search
warnings_exist {
  $schema->resultset('Artist')->search_rs(id => 4)
} qr/\Qsearch( %condition ) is deprecated/, 'Deprecation warning on ->search( %condition )';

# this has been warning for 4 years, killing
throws_ok {
  $schema->resultset('Artist')->find(artistid => 4);
} qr|expects either a column/value hashref, or a list of values corresponding to the columns of the specified unique constraint|;

is($schema->resultset("Artist")->count, 4, 'count ok');

# test find_or_new
{
  my $existing_obj = $schema->resultset('Artist')->find_or_new({
    artistid => 4,
  });

  is($existing_obj->name, 'Man With A Spoon', 'find_or_new: found existing artist');
  ok($existing_obj->in_storage, 'existing artist is in storage');

  my $new_obj = $schema->resultset('Artist')->find_or_new({
    artistid => 5,
    name     => 'find_or_new',
  });

  is($new_obj->name, 'find_or_new', 'find_or_new: instantiated a new artist');
  is($new_obj->in_storage, 0, 'new artist is not in storage');
}

my $cd = $schema->resultset("CD")->find(1);
my %cols = $cd->get_columns;

is(keys %cols, 6, 'get_columns number of columns ok');

is($cols{title}, 'Spoonful of bees', 'get_columns values ok');

%cols = ( title => 'Forkful of bees', year => 2005);
$cd->set_columns(\%cols);

is($cd->title, 'Forkful of bees', 'set_columns ok');

is($cd->year, 2005, 'set_columns ok');

$cd->discard_changes;

# check whether ResultSource->columns returns columns in order originally supplied
my @cd = $schema->source("CD")->columns;

is_deeply( \@cd, [qw/cdid artist title year genreid single_track/], 'column order');

$cd = $schema->resultset("CD")->search({ title => 'Spoonful of bees' }, { columns => ['title'] })->next;
is($cd->title, 'Spoonful of bees', 'subset of columns returned correctly');

$cd = $schema->resultset("CD")->search(undef, { '+columns' => [ { name => 'artist.name' } ], join => [ 'artist' ] })->find(1);

is($cd->title, 'Spoonful of bees', 'Correct CD returned with include');
is($cd->get_column('name'), 'Caterwauler McCrae', 'Additional column returned');

# check if new syntax +columns also works for this
$cd = $schema->resultset("CD")->search(undef, { '+columns' => [ { name => 'artist.name' } ], join => [ 'artist' ] })->find(1);

is($cd->title, 'Spoonful of bees', 'Correct CD returned with include');
is($cd->get_column('name'), 'Caterwauler McCrae', 'Additional column returned');

# check if new syntax for +columns select specifiers works for this
$cd = $schema->resultset("CD")->search(undef, { '+columns' => [ {artist_name => 'artist.name'} ], join => [ 'artist' ] })->find(1);

is($cd->title, 'Spoonful of bees', 'Correct CD returned with include');
is($cd->get_column('artist_name'), 'Caterwauler McCrae', 'Additional column returned');

# update_or_insert
$new = $schema->resultset("Track")->new( {
  trackid => 100,
  cd => 1,
  title => 'Insert or Update',
  last_updated_on => '1973-07-19 12:01:02'
} );
$new->update_or_insert;
ok($new->in_storage, 'update_or_insert insert ok');

# test in update mode
$new->title('Insert or Update - updated');
$new->update_or_insert;
is( $schema->resultset("Track")->find(100)->title, 'Insert or Update - updated', 'update_or_insert update ok');

SKIP: {
    skip "Tests require " . DBIx::Class::Optional::Dependencies->req_missing_for ('test_dt_sqlite'), 13
      unless DBIx::Class::Optional::Dependencies->req_ok_for ('test_dt_sqlite');

    # test get_inflated_columns with objects
    my $event = $schema->resultset('Event')->search->first;
    my %edata = $event->get_inflated_columns;
    is($edata{'id'}, $event->id, 'got id');
    isa_ok($edata{'starts_at'}, 'DateTime', 'start_at is DateTime object');
    isa_ok($edata{'created_on'}, 'DateTime', 'create_on DateTime object');
    is($edata{'starts_at'}, $event->starts_at, 'got start date');
    is($edata{'created_on'}, $event->created_on, 'got created date');


    # get_inflated_columns w/relation and accessor alias
    isa_ok($new->updated_date, 'DateTime', 'have inflated object via accessor');
    my %tdata = $new->get_inflated_columns;
    is($tdata{'trackid'}, 100, 'got id');
    isa_ok($tdata{'cd'}, 'DBICTest::CD', 'cd is CD object');
    is($tdata{'cd'}->id, 1, 'cd object is id 1');
    is(
        $tdata{'position'},
        $schema->resultset ('Track')->search ({cd => 1})->count,
        'Ordered assigned proper position',
    );
    is($tdata{'title'}, 'Insert or Update - updated');
    is($tdata{'last_updated_on'}, '1973-07-19T12:01:02');
    isa_ok($tdata{'last_updated_on'}, 'DateTime', 'inflated accessored column');
}

throws_ok (sub {
  $schema->class("Track")->load_components('DoesNotExist');
}, qr!Can't locate DBIx/Class/DoesNotExist.pm!, 'exception on nonexisting component');

is($schema->class("Artist")->field_name_for->{name}, 'artist name', 'mk_classdata usage ok');

my $search = [ { 'tags.tag' => 'Cheesy' }, { 'tags.tag' => 'Blue' } ];

my $or_rs = $schema->resultset("CD")->search_rs($search, { join => 'tags',
                                                  order_by => 'cdid' });
is($or_rs->all, 5, 'Joined search with OR returned correct number of rows');
is($or_rs->count, 5, 'Search count with OR ok');

my $collapsed_or_rs = $or_rs->search ({}, { distinct => 1 }); # induce collapse
is ($collapsed_or_rs->all, 4, 'Collapsed joined search with OR returned correct number of rows');
is ($collapsed_or_rs->count, 4, 'Collapsed search count with OR ok');

# make sure sure distinct on a grouped rs is warned about
{
  my $cd_rs = $schema->resultset ('CD')
                ->search ({}, { distinct => 1, group_by => 'title' });
  warnings_exist (sub {
    $cd_rs->next;
  }, qr/Useless use of distinct/, 'UUoD warning');
}

{
  my $tcount = $schema->resultset('Track')->search(
    {},
    {
      select => [ qw/position title/ ],
      distinct => 1,
    }
  );
  is($tcount->count, 13, 'multiple column COUNT DISTINCT ok');

  $tcount = $schema->resultset('Track')->search(
    {},
    {
      columns => [ qw/position title/ ],
      distinct => 1,
    }
  );
  is($tcount->count, 13, 'multiple column COUNT DISTINCT ok');

  $tcount = $schema->resultset('Track')->search(
    {},
    {
       group_by => [ qw/position title/ ]
    }
  );
  is($tcount->count, 13, 'multiple column COUNT DISTINCT using column syntax ok');
}

my $tag_rs = $schema->resultset('Tag')->search(
               [ { 'me.tag' => 'Cheesy' }, { 'me.tag' => 'Blue' } ]);

my $rel_rs = $tag_rs->search_related('cd', {}, { order_by => 'cd.cdid'} );

is($rel_rs->count, 5, 'Related search ok');

is($or_rs->next->cdid, $rel_rs->next->cdid, 'Related object ok');
$or_rs->reset;
$rel_rs->reset;

# at this point there should be no active statements
# (finish() was called everywhere, either explicitly via
# reset() or on DESTROY)
for (keys %{$schema->storage->dbh->{CachedKids}}) {
  fail("Unreachable cached statement still active: $_")
    if $schema->storage->dbh->{CachedKids}{$_}->FETCH('Active');
}

my $tag = $schema->resultset('Tag')->search(
  [ { 'me.tag' => 'Blue' } ],
  { columns => 'tagid' }
)->next;

ok($tag->has_column_loaded('tagid'), 'Has tagid loaded');
ok(!$tag->has_column_loaded('tag'), 'Has not tag loaded');

ok($schema->storage(), 'Storage available');

{
  my $rs = $schema->resultset("Artist")->search({
    -and => [
      artistid => { '>=', 1 },
      artistid => { '<', 3 }
    ]
  });

  $rs->update({ rank => 6134 });

  my $art;

  $art = $schema->resultset("Artist")->find(1);
  is($art->rank, 6134, 'updated first artist rank');

  $art = $schema->resultset("Artist")->find(2);
  is($art->rank, 6134, 'updated second artist rank');
}

# test source_name
{
  # source_name should be set for normal modules
  is($schema->source('CD')->source_name, 'CD', 'source_name is set to moniker');

  # test the result source that sets source_name explictly
  ok($schema->source('SourceNameArtists'), 'SourceNameArtists result source exists');

  my @artsn = $schema->resultset('SourceNameArtists')->search({}, { order_by => 'name DESC' });
  is(@artsn, 4, "Four artists returned");

  # make sure subclasses that don't set source_name are ok
  ok($schema->source('ArtistSubclass'), 'ArtistSubclass exists');
}

my $newbook = $schema->resultset( 'Bookmark' )->find(1);

lives_ok (sub { my $newlink = $newbook->link}, "stringify to false value doesn't cause error");

# test cascade_delete through many_to_many relations
{
  my $art_del = $schema->resultset("Artist")->find({ artistid => 1 });
  lives_ok (sub { $art_del->delete }, 'Cascading delete on Ordered has_many works' );  # real test in ordered.t
  is( $schema->resultset("CD")->search({artist => 1}), 0, 'Cascading through has_many top level.');
  is( $schema->resultset("CD_to_Producer")->search({cd => 1}), 0, 'Cascading through has_many children.');
}

# test column_info
{
  $schema->source("Artist")->{_columns}{'artistid'} = {};
  $schema->source("Artist")->column_info_from_storage(1);

  my $typeinfo = $schema->source("Artist")->column_info('artistid');
  is($typeinfo->{data_type}, 'INTEGER', 'column_info ok');
  $schema->source("Artist")->column_info('artistid');
  ok($schema->source("Artist")->{_columns_info_loaded} == 1, 'Columns info loaded flag set');
}

# test columns_info
{
  $schema->source("Artist")->{_columns}{'artistid'} = {};
  $schema->source("Artist")->column_info_from_storage(1);
  $schema->source("Artist")->{_columns_info_loaded} = 0;

  is_deeply (
    $schema->source('Artist')->columns_info,
    {
      artistid => {
        data_type => "INTEGER",
        default_value => undef,
        is_nullable => 0,
        size => undef
      },
      charfield => {
        data_type => "char",
        default_value => undef,
        is_nullable => 1,
        size => 10
      },
      name => {
        data_type => "varchar",
        default_value => undef,
        is_nullable => 1,
        is_numeric => 0,
        size => 100
      },
      rank => {
        data_type => "integer",
        default_value => 13,
        is_nullable => 0,
        size => undef
      },
    },
    'columns_info works',
  );

  ok($schema->source("Artist")->{_columns_info_loaded} == 1, 'Columns info loaded flag set');

  is_deeply (
    $schema->source('Artist')->columns_info([qw/artistid rank/]),
    {
      artistid => {
        data_type => "INTEGER",
        default_value => undef,
        is_nullable => 0,
        size => undef
      },
      rank => {
        data_type => "integer",
        default_value => 13,
        is_nullable => 0,
        size => undef
      },
    },
    'limited columns_info works',
  );
}

# test source_info
{
  my $expected = {
    "source_info_key_A" => "source_info_value_A",
    "source_info_key_B" => "source_info_value_B",
    "source_info_key_C" => "source_info_value_C",
  };

  my $sinfo = $schema->source("Artist")->source_info;

  is_deeply($sinfo, $expected, 'source_info data works');
}

# test remove_columns
{
  is_deeply(
    [$schema->source('CD')->columns],
    [qw/cdid artist title year genreid single_track/],
    'initial columns',
  );

  $schema->source('CD')->remove_columns('coolyear'); #should not delete year
  is_deeply(
    [$schema->source('CD')->columns],
    [qw/cdid artist title year genreid single_track/],
    'nothing removed when removing a non-existent column',
  );

  $schema->source('CD')->remove_columns('genreid', 'year');
  is_deeply(
    [$schema->source('CD')->columns],
    [qw/cdid artist title single_track/],
    'removed two columns',
  );

  my $priv_columns = $schema->source('CD')->_columns;
  ok(! exists $priv_columns->{'year'}, 'year purged from _columns');
  ok(! exists $priv_columns->{'genreid'}, 'genreid purged from _columns');
}

# test resultsource->table return value when setting
{
    my $class = $schema->class('Event');
    my $table = $class->table($class->table);
    is($table, $class->table, '->table($table) returns $table');
}

#make sure insert doesn't use set_column
{
  my $en_row = $schema->resultset('Encoded')->new_result({encoded => 'wilma'});
  is($en_row->encoded, 'amliw', 'new encodes');
  $en_row->insert;
  is($en_row->encoded, 'amliw', 'insert does not encode again');
}

#make sure multicreate encoding still works
{
  my $empl_rs = $schema->resultset('Employee');

  my $empl = $empl_rs->create ({
    name => 'Secret holder',
    secretkey => {
      encoded => 'CAN HAZ',
    },
  });
  is($empl->secretkey->encoded, 'ZAH NAC', 'correctly encoding on multicreate');

  my $empl2 = $empl_rs->create ({
    name => 'Same secret holder',
    secretkey => {
      encoded => 'CAN HAZ',
    },
  });
  is($empl2->secretkey->encoded, 'ZAH NAC', 'correctly encoding on preexisting multicreate');

  $empl_rs->create ({
    name => 'cat1',
    secretkey => {
      encoded => 'CHEEZBURGER',
      keyholders => [
        {
          name => 'cat2',
        },
        {
          name => 'cat3',
        },
      ],
    },
  });

  is($empl_rs->find({name => 'cat1'})->secretkey->encoded, 'REGRUBZEEHC', 'correct secret in database for empl1');
  is($empl_rs->find({name => 'cat2'})->secretkey->encoded, 'REGRUBZEEHC', 'correct secret in database for empl2');
  is($empl_rs->find({name => 'cat3'})->secretkey->encoded, 'REGRUBZEEHC', 'correct secret in database for empl3');

}

# make sure that obsolete handle-based source tracking continues to work for the time being
{
  my $handle = $schema->source('Artist')->handle;

  my $rowdata = { $schema->resultset('Artist')->next->get_columns };

  my $rs = DBIx::Class::ResultSet->new($handle);
  my $rs_result = $rs->next;
  isa_ok( $rs_result, 'DBICTest::Artist' );
  is_deeply (
    { $rs_result->get_columns },
    $rowdata,
    'Correct columns retrieved (rset/source link healthy)'
  );

  my $row = DBICTest::Artist->new({ -source_handle => $handle });
  is_deeply(
    { $row->get_columns },
    {},
    'No columns yet'
  );

  # store_column to fool the _orig_ident tracker
  $row->store_column('artistid', $rowdata->{artistid});
  $row->in_storage(1);

  $row->discard_changes;
  is_deeply(
    { $row->get_columns },
    $rowdata,
    'Storage refetch successful'
  );
}

# test to make sure that calling ->new() on a resultset object gives
# us a row object
{
    my $new_artist = $schema->resultset('Artist')->new({});
    isa_ok( $new_artist, 'DBIx::Class::Row', '$rs->new gives a row object' );
}


# make sure we got rid of the compat shims
SKIP: {
    my $remove_version = 0.083;
    skip "Remove in $remove_version", 3 if $DBIx::Class::VERSION < $remove_version;

    for (qw/compare_relationship_keys pk_depends_on resolve_condition/) {
      ok (! DBIx::Class::ResultSource->can ($_), "$_ no longer provided by DBIx::Class::ResultSource, removed before $remove_version");
    }
}

#------------------------------
# READ THIS BEFORE "FIXING"
#------------------------------
#
# make sure we got rid of discard_changes mess - this is a mess and a source
# of great confusion. Here I simply die if the methods are available, which
# is wrong on its own (we *have* to provide some sort of back-compat, even
# if with warnings). Here is how I envision things should actually be. Also
# note that a lot of the deprecation can be started today (i.e. the switch
# from get_from_storage to copy_from_storage). So:
#
# $row->discard_changes =>
#   warning, and delegation to reload_from_storage
#
# $row->reload_from_storage =>
#   does what discard changes did in 0.08 - issues a query to the db
#   and repopulates all column slots, regardless of dirty states etc.
#
# $row->revert_changes =>
#   does what discard_changes should have done initially (before it became
#   a dual-purpose call). In order to make this work we will have to
#   augment $row to carry its own initial-state, much like svn has a
#   copy of the current checkout in contrast to cvs.
#
# my $db_row = $row->get_from_storage =>
#   warns and delegates to an improved name copy_from_storage, with the
#   same semantics
#
# my $db_row = $row->copy_from_storage =>
#   a much better/descriptive name than get_from_storage
#
#------------------------------
# READ THIS BEFORE "FIXING"
#------------------------------
#
SKIP: {
    skip "Something needs to be done before 0.09", 2 if $DBIx::Class::VERSION < 0.09;

    my $row = $schema->resultset ('Artist')->next;

    for (qw/discard_changes get_from_storage/) {
      ok (! $row->can ($_), "$_ needs *some* sort of facelift before 0.09 ships - current state of affairs is unacceptable");
    }
}

throws_ok { $schema->resultset} qr/resultset\(\) expects a source name/, 'resultset with no argument throws exception';

done_testing;
