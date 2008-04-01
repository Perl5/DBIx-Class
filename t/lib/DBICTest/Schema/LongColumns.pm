package # hide from PAUSE
    DBICTest::Schema::LongColumns;

use base qw/DBIx::Class::Core/;

__PACKAGE__->table('long_columns');
__PACKAGE__->add_columns(
    'lcid' => {
        data_type => 'int',
        is_auto_increment => 1,
    },
    '64_character_column_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' => {
        data_type => 'int',
    },
    '32_character_column_aaaaaaaaaaaa' => {
        data_type => 'int',
    },
    '32_character_column_bbbbbbbbbbbb' => {
        data_type => 'int',
    },
    '16_character_col' => {
        data_type => 'int',
    },
    '8_char_c' => {
        data_type => 'int',
    },
);

__PACKAGE__->set_primary_key('lcid');

__PACKAGE__->add_unique_constraint([qw( 16_character_col 32_character_column_aaaaaaaaaaaa )]);

__PACKAGE__->add_unique_constraint([qw( 8_char_c 16_character_col 32_character_column_aaaaaaaaaaaa )]);

__PACKAGE__->add_unique_constraint([qw( 8_char_c 16_character_col 32_character_column_bbbbbbbbbbbb )]);

__PACKAGE__->add_unique_constraint([qw( 64_character_column_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa )]);

__PACKAGE__->belongs_to(
    'owner',
    'DBICTest::Schema::LongColumns',
    {
        'foreign.lcid' => 'self.64_character_column_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    },
);

__PACKAGE__->belongs_to(
    'owner2',
    'DBICTest::Schema::LongColumns',
    {
        'foreign.32_character_column_aaaaaaaaaaaa' => 'self.32_character_column_bbbbbbbbbbbb',
        'foreign.32_character_column_bbbbbbbbbbbb' => 'self.32_character_column_aaaaaaaaaaaa',
    },
);

__PACKAGE__->belongs_to(
    'owner3',
    'DBICTest::Schema::LongColumns',
    {
        'foreign.8_char_c' => 'self.16_character_col',
    },
);

1;
