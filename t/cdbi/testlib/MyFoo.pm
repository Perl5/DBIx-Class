package # hide from PAUSE
    MyFoo;

use warnings;
use strict;

use base 'MyBase';

use Date::Simple 3.03;

__PACKAGE__->set_table();
__PACKAGE__->columns(All => qw/myid name val tdate/);
__PACKAGE__->has_a(
  tdate   => 'Date::Simple',
  inflate => sub { Date::Simple->new(shift) },
  deflate => 'format',
);

# Disables the implicit autoinc-on-non-supplied-pk behavior
# (and the warning that goes with it)
# This is the same behavior as it was pre 0.082900
__PACKAGE__->column_info('myid')->{is_auto_increment} = 0;

#__PACKAGE__->find_column('tdate')->placeholder("IF(1, CURDATE(), ?)");

sub create_sql {
  return qq{
    myid mediumint not null auto_increment primary key,
    name varchar(50) not null default '',
    val  char(1) default 'A',
    tdate date not null
  };
}

1;

