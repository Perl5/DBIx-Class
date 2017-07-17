package # hide from PAUSE
    ActorAlias;

use strict;
use warnings;

use base 'DBIC::Test::SQLite';

__PACKAGE__->set_table( 'ActorAlias' );

__PACKAGE__->columns( Primary => 'id' );
__PACKAGE__->columns( All     => qw/ actor alias / );
__PACKAGE__->has_a( actor => 'Actor' );
__PACKAGE__->has_a( alias => 'Actor' );

# Disables the implicit autoinc-on-non-supplied-pk behavior
# (and the warning that goes with it)
# This is the same behavior as it was pre 0.082900
__PACKAGE__->column_info('id')->{is_auto_increment} = 0;

sub create_sql {
  return qq{
    id    INTEGER PRIMARY KEY,
    actor INTEGER,
    alias INTEGER
  }
}

1;

