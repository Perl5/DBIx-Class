package # hide from PAUSE
    Actor;

use strict;
use warnings;

use base 'DBIC::Test::SQLite';

__PACKAGE__->set_table('Actor');

__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(All     => qw/ Name Film Salary /);
__PACKAGE__->columns(TEMP    => qw/ nonpersistent /);
__PACKAGE__->add_constructor(salary_between => 'salary >= ? AND salary <= ?');

# Disables the implicit autoinc-on-non-supplied-pk behavior
# (and the warning that goes with it)
# This is the same behavior as it was pre 0.082900
__PACKAGE__->column_info('id')->{is_auto_increment} = 0;

sub mutator_name_for { "set_$_[1]" }

sub create_sql {
  return qq{
    id     INTEGER PRIMARY KEY,
    name   CHAR(40),
    film   VARCHAR(255),
    salary INT
  }
}

1;

