package # hide from PAUSE
    DBICTest::Schema::Quotes;

use warnings;
use strict;

use base 'DBICTest::BaseResult';

# Include all the common quote characters
__PACKAGE__->table('`with` [some] "quotes"');

__PACKAGE__->add_columns(
  '`has` [more] "quotes"' => {
    data_type => 'integer',
    is_auto_increment => 1,
    accessor => 'has_more_quotes',
  },
);

1;
