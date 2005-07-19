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

sub get {
  my ($class, $get, @rest) = @_;
  return $class->NEXT::get(lc $get, @rest);
}

sub set {
  my ($class, $set, @rest) = @_;
  return $class->NEXT::set(lc $set, @rest);
}

sub find_column {
  my ($class, $col) = @_;
  return $class->NEXT::find_column(lc $col);
}

sub _mk_accessors {
  my ($class, $type, @fields) = @_;
  my %fields;
  $fields{$_} = 1 for @fields,
                    map lc, grep { !defined &{"${class}::${_}"} } @fields;
  return $class->NEXT::_mk_accessors($type, keys %fields);
}

1;
