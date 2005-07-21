package DBIx::Class::CDBICompat::ColumnCase;

use strict;
use warnings;
use NEXT;

sub _register_column_group {
  my ($class, $group, @cols) = @_;
  return $class->NEXT::_register_column_group($group => map lc, @cols);
}

sub _register_columns {
  my ($class, @cols) = @_;
  return $class->NEXT::_register_columns(map lc, @cols);
}

sub get_column {
  my ($class, $get, @rest) = @_;
  return $class->NEXT::get_column(lc $get, @rest);
}

sub set_column {
  my ($class, $set, @rest) = @_;
  return $class->NEXT::set_column(lc $set, @rest);
}

sub store_column {
  my ($class, $set, @rest) = @_;
  return $class->NEXT::store_column(lc $set, @rest);
}

sub find_column {
  my ($class, $col) = @_;
  return $class->NEXT::find_column(lc $col);
}

sub _mk_group_accessors {
  my ($class, $type, $group, @fields) = @_;
  my %fields;
  $fields{$_} = 1 for @fields,
                    map lc, grep { !defined &{"${class}::${_}"} } @fields;
  return $class->NEXT::_mk_group_accessors($type, $group, keys %fields);
}

1;
