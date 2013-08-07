package # hide from PAUSE
    DBIx::Class::Relationship::BelongsTo;

# Documentation for these methods can be found in
# DBIx::Class::Relationship

use strict;
use warnings;
use Try::Tiny;
use namespace::clean;

our %_pod_inherit_config =
  (
   class_map => { 'DBIx::Class::Relationship::BelongsTo' => 'DBIx::Class::Relationship' }
  );

sub belongs_to {
  my ($class, $rel, $f_class, $cond, $attrs) = @_;

  # assume a foreign key constraint unless defined otherwise
  $attrs->{is_foreign_key_constraint} = 1
    if not exists $attrs->{is_foreign_key_constraint};
  $attrs->{undef_on_null_fk} = 1
    if not exists $attrs->{undef_on_null_fk};

  # no join condition or just a column name
  if (!ref $cond) {
    $class->ensure_class_loaded($f_class);
    my %f_primaries = map { $_ => 1 } try { $f_class->_pri_cols }
      catch {
        $class->throw_exception( "Can't infer join condition for '$rel' on ${class}: $_");
      };

    my ($pri, $too_many) = keys %f_primaries;
    $class->throw_exception(
      "Can't infer join condition for '$rel' on ${class}: "
    . "${f_class} has multiple primary keys"
    ) if $too_many;

    my $fk = defined $cond ? $cond : $rel;
    $class->throw_exception(
      "Can't infer join condition for '$rel' on ${class}: "
    . "'$fk' is not a column of $class"
    ) unless $class->has_column($fk);

    $cond = { "foreign.${pri}" => "self.${fk}" };

  }
  # explicit join condition
  elsif (ref $cond) {
    if (ref $cond eq 'HASH') { # ARRAY is also valid
      my $cond_rel;
      for (keys %$cond) {
        if (m/\./) { # Explicit join condition
          $cond_rel = $cond;
          last;
        }
        $cond_rel->{"foreign.$_"} = "self.".$cond->{$_};
      }
      $cond = $cond_rel;
    }
  }
  # dunno
  else {
    $class->throw_exception(
      'third argument for belongs_to must be undef, a column name, '.
      'or a join condition'
    );
  }

  my $acc_type = (
    ref $cond eq 'HASH'
      and
    keys %$cond == 1
      and
    (keys %$cond)[0] =~ /^foreign\./
      and
    $class->has_column($rel)
  ) ? 'filter' : 'single';

  my $fk_columns = ($acc_type eq 'single' and ref $cond eq 'HASH')
    ? { map { $_ =~ /^self\.(.+)/ ? ( $1 => 1 ) : () } (values %$cond ) }
    : undef
  ;

  $class->add_relationship($rel, $f_class,
    $cond,
    {
      accessor => $acc_type,
      $fk_columns ? ( fk_columns => $fk_columns ) : (),
      %{$attrs || {}}
    }
  );

  return 1;
}

# Attempt to remove the POD so it (maybe) falls off the indexer

#=head1 AUTHORS
#
#Alexander Hartmaier <Alexander.Hartmaier@t-systems.at>
#
#Matt S. Trout <mst@shadowcatsystems.co.uk>
#
#=cut

1;
