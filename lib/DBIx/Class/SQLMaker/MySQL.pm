package # Hide from PAUSE
  DBIx::Class::SQLMaker::MySQL;

use warnings;
use strict;

use base qw( DBIx::Class::SQLMaker );

#
# MySQL does not understand the standard INSERT INTO $table DEFAULT VALUES
# Adjust SQL here instead
#
sub insert {
  my $self = shift;

  if (! $_[1] or (ref $_[1] eq 'HASH' and !keys %{$_[1]} ) ) {
    my $table = $self->_quote($_[0]);
    return "INSERT INTO ${table} () VALUES ()"
  }

  return $self->next::method (@_);
}

# Allow STRAIGHT_JOIN's
sub _generate_join_clause {
    my ($self, $join_type) = @_;

    if( $join_type && $join_type =~ /^STRAIGHT\z/i ) {
        return ' STRAIGHT_JOIN '
    }

    return $self->next::method($join_type);
}

my $force_double_subq;
$force_double_subq = sub {
  my ($self, $sql) = @_;

  require Text::Balanced;
  my $new_sql;
  while (1) {

    my ($prefix, $parenthesized);

    ($parenthesized, $sql, $prefix) = do {
      # idiotic design - writes to $@ but *DOES NOT* throw exceptions
      local $@;
      Text::Balanced::extract_bracketed( $sql, '()', qr/[^\(]*/ );
    };

    # this is how an error is indicated, in addition to crapping in $@
    last unless $parenthesized;

    if ($parenthesized =~ $self->{_modification_target_referenced_re}) {
      # is this a select subquery?
      if ( $parenthesized =~ /^ \( \s* SELECT \s+ /xi ) {
        $parenthesized = "( SELECT * FROM $parenthesized `_forced_double_subquery` )";
      }
      # then drill down until we find it (if at all)
      else {
        $parenthesized =~ s/^ \( (.+) \) $/$1/x;
        $parenthesized = join ' ', '(', $self->$force_double_subq( $parenthesized ), ')';
      }
    }

    $new_sql .= $prefix . $parenthesized;
  }

  return $new_sql . $sql;
};

sub update {
  my $self = shift;

  # short-circuit unless understood identifier
  return $self->next::method(@_) unless $self->{_modification_target_referenced_re};

  my ($sql, @bind) = $self->next::method(@_);

  $sql = $self->$force_double_subq($sql)
    if $sql =~ $self->{_modification_target_referenced_re};

  return ($sql, @bind);
}

sub delete {
  my $self = shift;

  # short-circuit unless understood identifier
  return $self->next::method(@_) unless $self->{_modification_target_referenced_re};

  my ($sql, @bind) = $self->next::method(@_);

  $sql = $self->$force_double_subq($sql)
    if $sql =~ $self->{_modification_target_referenced_re};

  return ($sql, @bind);
}

#
# Support for MySQL lock clause syntax according to specification 
# including updates introduced in MySQL 8.0.1)
# FOR UPDATE | FOR SHARE [OF tbl_name [, tbl_name] ...] [NOWAIT | SKIP LOCKED]
#

my $lock_types = {
  update => 'FOR UPDATE',
  share => 'FOR SHARE',
  shared => 'LOCK IN SHARE MODE'  # Deprecated but maintained
};

my $lock_modifiers = {
  nowait => 'NOWAIT',
  skip_locked => 'SKIP LOCKED'
};

sub _lock_select {
  my ($self, $type) = @_;

  if ($type eq 'shared') {
    warnings::warnif(
      'deprecated',
       "'for => 'shared'' is deprecated. Please use 'for => 'share'' instead"
    );
  }
   
  # Handle hash-based configuration to support new featureset
  if (ref $type eq 'HASH') {
    my $lock_type = $type->{type};
    my $tables = $type->{of};
    my $modifier = $type->{modifier};
      
    my $lock_clause = $lock_types->{$lock_type} 
      || $self->throw_exception("Unknown SELECT .. FOR type '$lock_type' requested");

    # Add OF clause if tables are specified  
    if ($tables) {
      my @table_list = ref $tables eq 'ARRAY' ? @$tables : ($tables);
      if (@table_list) {
        my $quoted_tables = join(', ', 
          map { $self->_quote($_) } @table_list
        );
        $lock_clause .= " OF $quoted_tables";
      }
    }

    # Add modifier if specified  
    if ($modifier) {
      my $mod_sql = $lock_modifiers->{$modifier}
        || $self->throw_exception("Unknown lock modifier '$modifier' requested");
      $lock_clause .= " $mod_sql";
    }
      
    return " $lock_clause";
  }

  # Handle simple string types (for backward compatibility)
  my $sql = $lock_types->{$type}
    || $self->throw_exception("Unknown SELECT .. FOR type '$type' requested");
   
  return " $sql";
}

1;
