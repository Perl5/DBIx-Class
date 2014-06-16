package # hide from PAUSE
    Lazy;

use warnings;
use strict;

use base 'DBIC::Test::SQLite';

__PACKAGE__->set_table("Lazy");
__PACKAGE__->columns('Primary',   qw(this));
__PACKAGE__->columns('Essential', qw(opop));
__PACKAGE__->columns('things',    qw(this that));
__PACKAGE__->columns('horizon',   qw(eep orp));
__PACKAGE__->columns('vertical',  qw(oop opop));

sub create_sql {
  return qq{
    this INTEGER,
    that INTEGER,
    eep  INTEGER,
    orp  INTEGER,
    oop  INTEGER,
    opop INTEGER
  };
}

1;

