package DBICTest::Schema::BasicRels;

use base 'DBIx::Class::Core';

DBICTest::Schema::Artist->has_many(cds => 'DBICTest::Schema::CD', undef,
                                     { order_by => 'year' });
DBICTest::Schema::Artist->has_many(twokeys => 'DBICTest::Schema::TwoKeys');
DBICTest::Schema::Artist->has_many(onekeys => 'DBICTest::Schema::OneKey');

DBICTest::Schema::CD->belongs_to('artist', 'DBICTest::Schema::Artist');

DBICTest::Schema::CD->has_many(tracks => 'DBICTest::Schema::Track');
DBICTest::Schema::CD->has_many(tags => 'DBICTest::Schema::Tag');

DBICTest::Schema::CD->might_have(liner_notes => 'DBICTest::Schema::LinerNotes',
                                  undef, { proxy => [ qw/notes/ ] });

DBICTest::Schema::SelfRefAlias->belongs_to(
  self_ref => 'DBICTest::Schema::SelfRef');

DBICTest::Schema::SelfRefAlias->belongs_to(
  alias => 'DBICTest::Schema::SelfRef');

DBICTest::Schema::SelfRef->has_many(
  aliases => 'DBICTest::Schema::SelfRefAlias' => 'self_ref');

DBICTest::Schema::Tag->belongs_to('cd', 'DBICTest::Schema::CD');

DBICTest::Schema::Track->belongs_to('cd', 'DBICTest::Schema::CD');

DBICTest::Schema::Track->belongs_to('disc', 'DBICTest::Schema::CD', 'cd');

DBICTest::Schema::TwoKeys->belongs_to('artist', 'DBICTest::Schema::Artist');

DBICTest::Schema::TwoKeys->belongs_to('cd', 'DBICTest::Schema::CD');

1;
