use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;

#
# The test must be performed on non-registered result classes
#
{
  package DBICTest::Thing;
  use warnings;
  use strict;
  use base qw/DBIx::Class::Core/;
  __PACKAGE__->table('thing');
  __PACKAGE__->add_columns(qw/id ancestor_id/);
  __PACKAGE__->set_primary_key('id');
  __PACKAGE__->has_many(children => __PACKAGE__, 'id');
  __PACKAGE__->belongs_to(parent => __PACKAGE__, 'id', { join_type => 'left' } );

  __PACKAGE__->has_many(subthings => 'DBICTest::SubThing', 'thing_id');
}

{
  package DBICTest::SubThing;
  use warnings;
  use strict;
  use base qw/DBIx::Class::Core/;
  __PACKAGE__->table('subthing');
  __PACKAGE__->add_columns(qw/thing_id/);
  __PACKAGE__->belongs_to(thing => 'DBICTest::Thing', 'thing_id');
  __PACKAGE__->belongs_to(thing2 => 'DBICTest::Thing', 'thing_id', { join_type => 'left' } );
}

my $schema = DBICTest->init_schema;

for my $without_schema (1,0) {

  my ($t, $s) = $without_schema
    ? (qw/DBICTest::Thing DBICTest::SubThing/)
    : do {
      $schema->register_class(relinfo_thing => 'DBICTest::Thing');
      $schema->register_class(relinfo_subthing => 'DBICTest::SubThing');

      map { $schema->source ($_) } qw/relinfo_thing relinfo_subthing/;
    }
  ;

  is_deeply(
    [ sort $t->relationships ],
    [qw/ children parent subthings/],
    "Correct relationships on $t",
  );

  is_deeply(
    [ sort $s->relationships ],
    [qw/ thing thing2 /],
    "Correct relationships on $s",
  );

  is_deeply(
    _instance($s)->reverse_relationship_info('thing'),
    { subthings => $t->relationship_info('subthings') },
    'reverse_rel_info works cross-class belongs_to direction',
  );
  is_deeply(
    _instance($s)->reverse_relationship_info('thing2'),
    { subthings => $t->relationship_info('subthings') },
    'reverse_rel_info works cross-class belongs_to direction 2',
  );

  is_deeply(
    _instance($t)->reverse_relationship_info('subthings'),
    { map { $_ => $s->relationship_info($_) } qw/thing thing2/ },
    'reverse_rel_info works cross-class has_many direction',
  );

  is_deeply(
    _instance($t)->reverse_relationship_info('parent'),
    { children => $t->relationship_info('children') },
    'reverse_rel_info works in-class belongs_to direction',
  );
  is_deeply(
    _instance($t)->reverse_relationship_info('children'),
    { parent => $t->relationship_info('parent') },
    'reverse_rel_info works in-class has_many direction',
  );
}

sub _instance {
  $_[0]->isa('DBIx::Class::ResultSource')
    ? $_[0]
    : $_[0]->result_source_instance
}

done_testing;
