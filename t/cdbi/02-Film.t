use strict;
use warnings;

use Test::More;
use Scalar::Util 'refaddr';
use namespace::clean;
$| = 1;

INIT {
  use lib 't/cdbi/testlib';
  use Film;
}

ok(Film->can('db_Main'), 'set_db()');
is(Film->__driver, "SQLite", "Driver set correctly");

{
  my $nul = eval { Film->retrieve() };
  is $nul, undef, "Can't retrieve nothing";
  like $@, qr/./, "retrieve needs parameters";    # TODO fix this...
}

{
  eval { my $id = Film->id };
  like $@, qr/class method/, "Can't get id with no object";
}

{
  eval { my $id = Film->title };
  #like $@, qr/class method/, "Can't get title with no object";
  ok $@, "Can't get title with no object";
}

eval { my $duh = Film->insert; };
like $@, qr/create needs a hashref/, "needs a hashref";

ok +Film->create_test_film;

my $btaste = Film->retrieve('Bad Taste');
isa_ok $btaste, 'Film';
is($btaste->Title,             'Bad Taste',     'Title() get');
is($btaste->Director,          'Peter Jackson', 'Director() get');
is($btaste->Rating,            'R',             'Rating() get');
is($btaste->NumExplodingSheep, 1,               'NumExplodingSheep() get');

{
  my $bt2 = Film->find_or_create(Title => 'Bad Taste');
  is $bt2->Director, $btaste->Director, "find_or_create";
  my @bt = Film->search(Title => 'Bad Taste');
  is @bt, 1, " doesn't create a new one";
}

ok my $gone = Film->find_or_create(
  {
    Title             => 'Gone With The Wind',
    Director          => 'Bob Baggadonuts',
    Rating            => 'PG',
    NumExplodingSheep => 0
  }
  ),
  "Add Gone With The Wind";
isa_ok $gone, 'Film';
ok $gone = Film->retrieve(Title => 'Gone With The Wind'),
  "Fetch it back again";
isa_ok $gone, 'Film';

# Shocking new footage found reveals bizarre Scarlet/sheep scene!
is($gone->NumExplodingSheep, 0, 'NumExplodingSheep() get again');
$gone->NumExplodingSheep(5);
is($gone->NumExplodingSheep, 5, 'NumExplodingSheep() set');
is($gone->numexplodingsheep, 5, 'numexplodingsheep() set');

is($gone->Rating, 'PG', 'Rating() get again');
$gone->Rating('NC-17');
is($gone->Rating, 'NC-17', 'Rating() set');
$gone->update;

{
  my @films = eval { Film->retrieve_all };
  cmp_ok(@films, '==', 2, "We have 2 films in total");
}

# EXTRA TEST: added by mst to check a bug found by Numa
cmp_ok(Film->count_all, '==', 2, "count_all confirms 2 films");

my $gone_copy = Film->retrieve('Gone With The Wind');
ok($gone->NumExplodingSheep == 5, 'update()');
ok($gone->Rating eq 'NC-17', 'update() again');

# Grab the 'Bladerunner' entry.
Film->create(
  {
    Title    => 'Bladerunner',
    Director => 'Bob Ridley Scott',
    Rating   => 'R'
  }
);

my $blrunner = Film->retrieve('Bladerunner');
is(ref $blrunner, 'Film', 'retrieve() again');
is $blrunner->Title,    'Bladerunner',      "Correct title";
is $blrunner->Director, 'Bob Ridley Scott', " and Director";
is $blrunner->Rating,   'R',                " and Rating";
is $blrunner->NumExplodingSheep, undef, " and sheep";

# Make a copy of 'Bladerunner' and create an entry of the directors cut
my $blrunner_dc = $blrunner->copy(
  {
    title  => "Bladerunner: Director's Cut",
    rating => "15",
  }
);
is(ref $blrunner_dc, 'Film', "copy() produces a film");
is($blrunner_dc->Title,    "Bladerunner: Director's Cut", 'Title correct');
is($blrunner_dc->Director, 'Bob Ridley Scott',            'Director correct');
is($blrunner_dc->Rating,   '15',                          'Rating correct');
is($blrunner_dc->NumExplodingSheep, undef, 'Sheep correct');

# Set up own SQL:
{
  Film->add_constructor(title_asc  => "title LIKE ? ORDER BY title");
  Film->add_constructor(title_desc => "title LIKE ? ORDER BY title DESC");
    Film->add_constructor(title_asc_nl => q{
        title LIKE ?
        ORDER BY title
        LIMIT 1
    });

  {
    my @films = Film->title_asc("Bladerunner%");
    is @films, 2, "We have 2 Bladerunners";
    is $films[0]->Title, $blrunner->Title, "Ordered correctly";
  }
  {
    my @films = Film->title_desc("Bladerunner%");
    is @films, 2, "We have 2 Bladerunners";
    is $films[0]->Title, $blrunner_dc->Title, "Ordered correctly";
  }
  {
    my @films = Film->title_asc_nl("Bladerunner%");
    is @films, 1, "We have 2 Bladerunners";
    is $films[0]->Title, $blrunner->Title, "Ordered correctly";
  }
}

# Multi-column search
{
  my @films = $blrunner->search (title => { -like => "Bladerunner%"}, rating => '15');
  is @films, 1, "Only one Bladerunner is a 15";
}

# Inline SQL
{
  my @films = Film->retrieve_from_sql("numexplodingsheep > 0 ORDER BY title");
  is @films, 2, "Inline SQL";
  is $films[0]->id, $btaste->id, "Correct film";
  is $films[1]->id, $gone->id,   "Correct film";
}

# Inline SQL removes WHERE
{
  my @films =
    Film->retrieve_from_sql(" WHErE numexplodingsheep > 0 ORDER BY title");
  is @films, 2, "Inline SQL";
  is $films[0]->id, $btaste->id, "Correct film";
  is $films[1]->id, $gone->id,   "Correct film";
}

eval {
  my $ishtar = Film->insert({ Title => 'Ishtar', Director => 'Elaine May' });
  my $mandn =
    Film->insert({ Title => 'Mikey and Nicky', Director => 'Elaine May' });
  my $new_leaf =
    Film->insert({ Title => 'A New Leaf', Director => 'Elaine May' });

#use Data::Dumper; die Dumper(Film->search( Director => 'Elaine May' ));
  cmp_ok(Film->search(Director => 'Elaine May'), '==', 3,
    "3 Films by Elaine May");
  ok(Film->retrieve('Ishtar')->delete,
    "Ishtar doesn't deserve an entry any more");
  ok(!Film->retrieve('Ishtar'), 'Ishtar no longer there');
  {
    my $deprecated = 0;
    local $SIG{__WARN__} = sub { $deprecated++ if $_[0] =~ /deprecated/ };
    ok(
      Film->delete(Director => 'Elaine May'),
      "In fact, delete all films by Elaine May"
    );
    cmp_ok(Film->search(Director => 'Elaine May'), '==',
      0, "0 Films by Elaine May");
    is $deprecated, 0, "No deprecated warnings from compat layer";
  }
};
is $@, '', "No problems with deletes";

# Find all films which have a rating of NC-17.
my @films = Film->search('Rating', 'NC-17');
is(scalar @films, 1, ' search returns one film');
is($films[0]->id, $gone->id, ' ... the correct one');

# Find all films which were directed by Bob
@films = Film->search ( { 'Director' => { -like => 'Bob %' } });
is(scalar @films, 3, ' search_like returns 3 films');
ok(
  eq_array(
    [ sort map { $_->id } @films ],
    [ sort map { $_->id } $blrunner_dc, $gone, $blrunner ]
  ),
  'the correct ones'
);

# Find Ridley Scott films which don't have vomit
@films =
  Film->search(numExplodingSheep => undef, Director => 'Bob Ridley Scott');
is(scalar @films, 2, ' search where attribute is null returns 2 films');
ok(
  eq_array(
    [ sort map { $_->id } @films ],
    [ sort map { $_->id } $blrunner_dc, $blrunner ]
  ),
  'the correct ones'
);

# Test that a disconnect doesnt harm anything.
{
    # SQLite is loud on disconnect/reconnect.
    # This is solved in DBIC but not in ContextualFetch
    local $SIG{__WARN__} = sub {
      warn @_ unless $_[0] =~
        /active statement handles|inactive database handle/;
    };

    Film->db_Main->disconnect;
    @films = Film->search({ Rating => 'NC-17' });
    ok(@films == 1 && $films[0]->id eq $gone->id, 'auto reconnection');

    # Test discard_changes().
    my $orig_director = $btaste->Director;
    $btaste->Director('Lenny Bruce');
    is($btaste->Director, 'Lenny Bruce', 'set new Director');
    $btaste->discard_changes;
    is($btaste->Director, $orig_director, 'discard_changes()');
}

SKIP: {
  skip "ActiveState perl produces additional warnings", 3
          if ($^O eq 'MSWin32');

  Film->autoupdate(1);
  my $btaste2 = Film->retrieve($btaste->id);
  $btaste->NumExplodingSheep(18);
  my @warnings;
  local $SIG{__WARN__} = sub { push(@warnings, @_); };
  {

    # unhook from live object cache, so next one is not from cache
    $btaste2->remove_from_object_index;
    my $btaste3 = Film->retrieve($btaste->id);
    is $btaste3->NumExplodingSheep, 18, "Class based AutoCommit";
    $btaste3->autoupdate(0);    # obj a/c should override class a/c
    is @warnings, 0, "No warnings so far";
    $btaste3->NumExplodingSheep(13);
  }
  is @warnings, 1, "DESTROY without update warns";
  Film->autoupdate(0);
}

{                               # update unchanged object
  my $film   = Film->retrieve($btaste->id);
  my $retval = $film->update;
  is $retval, -1, "Unchanged object";
}

{                               # update deleted object
  my $rt = "Royal Tenenbaums";
  my $ten = Film->insert({ title => $rt, Rating => "R" });
  $ten->rating(18);
  Film->set_sql(drt => "DELETE FROM __TABLE__ WHERE title = ?");
  Film->sql_drt->execute($rt);
  my @films = Film->search({ title => $rt });
  is @films, 0, "RT gone";
  my $retval = eval { $ten->update };
  like $@, qr/row not found/, "Update deleted object throws error";
  $ten->discard_changes;
}

{
  $btaste->autoupdate(1);
  $btaste->NumExplodingSheep(32);
  my $btaste2 = Film->retrieve($btaste->id);
  is $btaste2->NumExplodingSheep, 32, "Object based AutoCommit";
  $btaste->autoupdate(0);
}

# Primary key of 0
{
  my $zero = Film->insert({ Title => 0, Rating => "U" });
  ok defined $zero, "Create 0";
  ok my $ret = Film->retrieve(0), "Retrieve 0";
  is $ret->Title,  0,   "Title OK";
  is $ret->Rating, "U", "Rating OK";
}

# Change after_update policy
SKIP: {
        skip "DBIx::Class compat doesn't handle the exists stuff quite right yet", 4;
  my $bt = Film->retrieve($btaste->id);
  $bt->autoupdate(1);

  $bt->rating("17");
  ok !$bt->_attribute_exists('rating'), "changed column needs reloaded";
  ok $bt->_attribute_exists('title'), "but we still have the title";

  # Don't re-load
  $bt->add_trigger(
    after_update => sub {
      my ($self, %args) = @_;
      my $discard_columns = $args{discard_columns};
      @$discard_columns = qw/title/;
    }
  );
  $bt->rating("19");
  ok $bt->_attribute_exists('rating'), "changed column needs reloaded";
  ok !$bt->_attribute_exists('title'), "but no longer have the title";
}

# Make sure that we can have other accessors. (Bugfix in 0.28)
if (0) {
  Film->mk_accessors(qw/temp1 temp2/);
  my $blrunner = Film->retrieve('Bladerunner');
  $blrunner->temp1("Foo");
  $blrunner->NumExplodingSheep(2);
  eval { $blrunner->update };
  ok(!$@, "Other accessors");
}

# overloading
{
  is "$blrunner", "Bladerunner", "stringify";

  ok(Film->columns(Stringify => 'rating'), "Can change stringify column");
  is "$blrunner", "R", "And still stringifies correctly";

  ok(
    Film->columns(Stringify => qw/title rating/),
    "Can have multiple stringify columns"
  );
  is "$blrunner", "Bladerunner/R", "And still stringifies correctly";

  no warnings 'once';
  local *Film::stringify_self = sub { join ":", $_[0]->title, $_[0]->rating };
  is "$blrunner", "Bladerunner:R", "Provide stringify_self()";
}

{
  {
    ok my $byebye = DeletingFilm->insert(
      {
        Title  => 'Goodbye Norma Jean',
        Rating => 'PG',
      }
      ),
      "Add a deleting Film";

    isa_ok $byebye, 'DeletingFilm';
    isa_ok $byebye, 'Film';
    ok(Film->retrieve('Goodbye Norma Jean'), "Fetch it back again");
  }
  my $film;
  eval { $film = Film->retrieve('Goodbye Norma Jean') };
  ok !$film, "It destroys itself";
}

SKIP: {
    skip "Caching has been removed", 5
        if Film->isa("DBIx::Class::CDBICompat::NoObjectIndex");

  # my bad taste is your bad taste
  my $btaste  = Film->retrieve('Bad Taste');
  my $btaste2 = Film->retrieve('Bad Taste');
  is refaddr $btaste, refaddr $btaste2,
    "Retrieving twice gives ref to same object";

  my ($btaste5) = Film->search(title=>'Bad Taste');
  is refaddr $btaste, refaddr $btaste5,
    "Searching also gives ref to same object";

  $btaste2->remove_from_object_index;
  my $btaste3 = Film->retrieve('Bad Taste');
  isnt refaddr $btaste2, refaddr $btaste3,
    "Removing from object_index and retrieving again gives new object";

  $btaste3->clear_object_index;
  my $btaste4 = Film->retrieve('Bad Taste');
  isnt refaddr $btaste2, refaddr $btaste4,
    "Clearing cache and retrieving again gives new object";

  $btaste=Film->insert({
    Title             => 'Bad Taste 2',
    Director          => 'Peter Jackson',
    Rating            => 'R',
    NumExplodingSheep => 2,
  });
  $btaste2 = Film->retrieve('Bad Taste 2');
  is refaddr $btaste, refaddr $btaste2,
    "Creating and retrieving gives ref to same object";

}

done_testing;
