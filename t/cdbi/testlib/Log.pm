package # hide from PAUSE
    Log;

use warnings;
use strict;

use base 'MyBase';

use Time::Piece::MySQL;
use POSIX;

__PACKAGE__->set_table();
__PACKAGE__->columns(All => qw/id message datetime_stamp/);
__PACKAGE__->has_a(
  datetime_stamp => 'Time::Piece',
  inflate        => 'from_mysql_datetime',
  deflate        => 'mysql_datetime'
);

# Disables the implicit autoinc-on-non-supplied-pk behavior
# (and the warning that goes with it)
# This is the same behavior as it was pre 0.082900
__PACKAGE__->column_info('id')->{is_auto_increment} = 0;

__PACKAGE__->add_trigger(before_create => \&set_dts);
__PACKAGE__->add_trigger(before_update => \&set_dts);

sub set_dts {
  shift->datetime_stamp(
    POSIX::strftime('%Y-%m-%d %H:%M:%S', localtime(time)));
}

sub create_sql {
  return qq{
    id             INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    message        VARCHAR(255),
    datetime_stamp DATETIME
  };
}

1;

