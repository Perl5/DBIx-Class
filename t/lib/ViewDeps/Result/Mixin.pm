package # hide from PAUSE
    ViewDeps::Result::Mixin;
## Used in 105view_deps.t

use strict;
use warnings;
use parent qw(DBIx::Class::Core);

__PACKAGE__->table('mixin');

__PACKAGE__->add_columns(
  id => {
    data_type => 'integer', is_auto_increment => 1, sequence => 'foo_id_seq'
  },
  words => { data_type => 'text' }
);

__PACKAGE__->set_primary_key('id');

1;
