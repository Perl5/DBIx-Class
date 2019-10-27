package DBICTest::SQLMRebase;

use warnings;
use strict;

our @ISA = qw( DBIx::Class::SQLMaker::ClassicExtensions SQL::Abstract::Classic );

__PACKAGE__->mk_group_accessors( simple => '__select_counter' );

sub select {
  $_[0]->{__select_counter}++;
  shift->next::method(@_);
}

1;
