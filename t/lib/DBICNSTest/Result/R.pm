package DBICNSTest::Result::R;

use warnings;
use strict;

use base qw/DBIx::Class::Core/;
__PACKAGE__->table('r');
__PACKAGE__->add_columns('r');
__PACKAGE__->belongs_to(
  a => 'DBICNSTest::Result::A',
  { 'foreign.a' => 'this.r' },
);
1;
