package # hide from PAUSE
    DBIx::Class::Relationship::HasOne;

use strict;
use warnings;
use DBIx::Class::Carp;
use Try::Tiny;
use namespace::clean;

our %_pod_inherit_config =
  (
   class_map => { 'DBIx::Class::Relationship::HasOne' => 'DBIx::Class::Relationship' }
  );

sub might_have {
  shift->_has_one('LEFT' => @_);
}

sub has_one {
  shift->_has_one(undef() => @_);
}

sub _has_one {
  my ($class, $join_type, $rel, $f_class, $cond, $attrs) = @_;
  unless (ref $cond) {
    $class->ensure_class_loaded($f_class);

    my $pri = $class->result_source_instance->_single_pri_col_or_die;

    my $f_class_loaded = try { $f_class->columns };
    my ($f_key,$guess);
    if (defined $cond && length $cond) {
      $f_key = $cond;
      $guess = "caller specified foreign key '$f_key'";
    } elsif ($f_class_loaded && $f_class->has_column($rel)) {
      $f_key = $rel;
      $guess = "using given relationship name '$rel' as foreign key column name";
    } elsif ($f_class_loaded and my $f_pri = try {
      $f_class->result_source_instance->_single_pri_col_or_die
    }) {
      $f_key = $f_pri;
      $guess = "using primary key of foreign class for foreign key";
    }

    $class->throw_exception(
      "No such column '$f_key' on foreign class ${f_class} ($guess)"
    ) if $f_class_loaded && !$f_class->has_column($f_key);

    $cond = { "foreign.${f_key}" => "self.${pri}" };
  }
  $class->_validate_has_one_condition($cond);

  my $default_cascade = ref $cond eq 'CODE' ? 0 : 1;

  $class->add_relationship($rel, $f_class,
   $cond,
   { accessor => 'single',
     cascade_update => $default_cascade,
     cascade_delete => $default_cascade,
     ($join_type ? ('join_type' => $join_type) : ()),
     %{$attrs || {}} });
  1;
}

sub _validate_has_one_condition {
  my ($class, $cond )  = @_;

  return if $ENV{DBIC_DONT_VALIDATE_RELS};
  return unless 'HASH' eq ref $cond;
  foreach my $foreign_id ( keys %$cond ) {
    my $self_id = $cond->{$foreign_id};

    # we can ignore a bad $self_id because add_relationship handles this
    # warning
    return unless $self_id =~ /^self\.(.*)$/;
    my $key = $1;
    $class->throw_exception("Defining rel on ${class} that includes '$key' but no such column defined here yet")
        unless $class->has_column($key);
    my $column_info = $class->column_info($key);
    if ( $column_info->{is_nullable} ) {
      carp(qq'"might_have/has_one" must not be on columns with is_nullable set to true ($class/$key). This might indicate an incorrect use of those relationship helpers instead of belongs_to.');
    }
  }
}

1;
