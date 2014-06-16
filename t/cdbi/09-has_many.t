use strict;
use warnings;
use Test::More;

use lib 't/cdbi/testlib';
use Film;
use Actor;
Actor->has_a(Film => 'Film');
Film->has_many(actors => 'Actor', { order_by => 'name' });
is(Actor->primary_column, 'id', "Actor primary OK");

ok(Actor->can('Salary'), "Actor table set-up OK");
ok(Film->can('actors'),  " and have a suitable method in Film");

Film->create_test_film;

ok(my $btaste = Film->retrieve('Bad Taste'), "We have Bad Taste");

ok(
  my $pvj = Actor->create(
    {
      Name   => 'Peter Vere-Jones',
      Film   => undef,
      Salary => '30_000',             # For a voice!
    }
  ),
  'create Actor'
);
is $pvj->Name, "Peter Vere-Jones", "PVJ name ok";
is $pvj->Film, undef, "No film";
ok $pvj->set_Film($btaste), "Set film";
$pvj->update;
is $pvj->Film->id, $btaste->id, "Now film";
{
  my @actors = $btaste->actors;
  is(@actors, 1, "Bad taste has one actor");
  is($actors[0]->Name, $pvj->Name, " - the correct one");
}

my %pj_data = (
  Name   => 'Peter Jackson',
  Salary => '0',               # it's a labour of love
);

eval { my $pj = Film->add_to_actors(\%pj_data) };
like $@, qr/class/, "add_to_actors must be object method";

eval { my $pj = $btaste->add_to_actors(%pj_data) };
like $@, qr/expects a hashref/, "add_to_actors takes hash";

ok(
  my $pj = $btaste->add_to_actors(
    {
      Name   => 'Peter Jackson',
      Salary => '0',               # it's a labour of love
    }
  ),
  'add_to_actors'
);
is $pj->Name,  "Peter Jackson",    "PJ ok";
is $pvj->Name, "Peter Vere-Jones", "PVJ still ok";

{
  my @actors = $btaste->actors;
  is @actors, 2, " - so now we have 2";
  is $actors[0]->Name, $pj->Name,  "PJ first";
  is $actors[1]->Name, $pvj->Name, "PVJ first";
}

eval {
  my @actors = $btaste->actors(Name => $pj->Name);
  is @actors, 1, "One actor from restricted (sorted) has_many";
  is $actors[0]->Name, $pj->Name, "It's PJ";
};
is $@, '', "No errors";

my $as = Actor->create(
  {
    Name   => 'Arnold Schwarzenegger',
    Film   => 'Terminator 2',
    Salary => '15_000_000'
  }
);

eval { $btaste->actors($pj, $pvj, $as) };
ok $@, $@;
is($btaste->actors, 2, " - so we still only have 2 actors");

my @bta_before = Actor->search(Film => 'Bad Taste');
is(@bta_before, 2, "We have 2 actors in bad taste");
ok($btaste->delete, "Delete bad taste");
my @bta_after = Actor->search(Film => 'Bad Taste');
is(@bta_after, 0, " - after deleting there are no actors");

# While we're here, make sure Actors have unreadable mutators and
# unwritable accessors

eval { $as->Name("Paul Reubens") };
ok $@, $@;
eval { my $name = $as->set_Name };
ok $@, $@;

is($as->Name, 'Arnold Schwarzenegger', "Arnie's still Arnie");


# Test infering of the foreign key of a has_many from an existing has_a
{
    use Thing;
    use OtherThing;

    Thing->has_a(that_thing => "OtherThing");
    OtherThing->has_many(things => "Thing");

    my $other_thing = OtherThing->create({ id => 1 });
    Thing->create({ id => 1, that_thing => $other_thing });
    Thing->create({ id => 2, that_thing => $other_thing });

    is_deeply [sort map { $_->id } $other_thing->things], [1,2];
}

done_testing;
