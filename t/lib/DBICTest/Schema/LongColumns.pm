package # hide from PAUSE  
    DBICTest::Schema::LongColumns;

use base qw/DBIx::Class::Core/;

__PACKAGE__->table('long_columns');
__PACKAGE__->add_columns(
    'lcid' => {
        data_type => 'int',
        is_auto_increment => 1,
    },
    '_64_character_column_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' => {
        data_type => 'int',
    },
    '_32_character_column_aaaaaaaaaaa' => {
        data_type => 'int',
    },
    '_32_character_column_bbbbbbbbbbb' => {
        data_type => 'int',
    },
    '_16_chars_column' => {
        data_type => 'int',
    },
    '_8_chr_c' => {
        data_type => 'int',
    },
);

__PACKAGE__->set_primary_key('lcid');

__PACKAGE__->add_unique_constraint([qw( _16_chars_column _32_character_column_aaaaaaaaaaa )]);

__PACKAGE__->add_unique_constraint([qw( _8_chr_c _16_chars_column _32_character_column_aaaaaaaaaaa )]);

__PACKAGE__->add_unique_constraint([qw( _8_chr_c _16_chars_column _32_character_column_bbbbbbbbbbb )]);

__PACKAGE__->add_unique_constraint([qw( _64_character_column_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa )]);

__PACKAGE__->belongs_to(
    'owner',
    'DBICTest::Schema::LongColumns',
    {
        'foreign.lcid' => 'self._64_character_column_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    },
);

__PACKAGE__->belongs_to(
    'owner2',
    'DBICTest::Schema::LongColumns',
    {
        'foreign._32_character_column_aaaaaaaaaaa' => 'self._32_character_column_bbbbbbbbbbb',
        'foreign._32_character_column_bbbbbbbbbbb' => 'self._32_character_column_aaaaaaaaaaa',
    },
);

__PACKAGE__->belongs_to(
    'owner3',
    'DBICTest::Schema::LongColumns',
    {
        'foreign._8_chr_c' => 'self._16_chars_column',
    },
);

1;
