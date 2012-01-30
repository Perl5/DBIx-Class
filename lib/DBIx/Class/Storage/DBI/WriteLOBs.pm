package DBIx::Class::Storage::DBI::WriteLOBs;

use strict;
use warnings;
use base 'DBIx::Class::Storage::DBI';
use mro 'c3';
use Data::Dumper::Concise 'Dumper';
use Try::Tiny;
use namespace::clean;

=head1 NAME

DBIx::Class::Storage::DBI::WriteLOBs - Storage component for RDBMS drivers that
need to use a special API for writing LOBs

=head1 DESCRIPTION

This is a storage component for database drivers that need to use an API outside
of the normal L<DBI> APIs for writing LOB values. This component implements
C<insert>, C<update> and C<insert_bulk>.

=cut

# REQUIRED METHODS
#
# The following methods must be implemented by the composing class:
#
# _write_lobs
#
# Arguments: $source, \%lobs, \%where
#
# Writes %lobs which is a column-value hash to the row pointed to by %where using
# the driver's DBD API. It is expected that the columns are already LOBs, the
# method is expected to truncate them before writing to them.
#
# _empty_lob
#
# Arguments: $source, $col
#
# Return Value: \"literal SQL"
#
# Returns the field to bind in the insert/update query in place of the LOB, for
# example C<\"''"> or C<\'EMPTY_BLOB()'>.
#
# _open_cursors_while_writing_lobs_allowed
#
# Arguments: NONE
#
# Optional. Should return 0 if the database does not allow having open cursors
# while writing LOBs. If not defined, it is assumed to be true.
#
# PROVIDED METHODS
#
# Private methods for your own implementations of the DML operations. If you
# implement them yourself, you may also set:
#
#   local $self->{_skip_writelobs_impl} = 1;
#
# to shortcircuit the inherited ones for a minor speedup.

sub _is_lob_column {
  my ($self, $source, $column) = @_;

  return $self->_is_lob_type($source->column_info($column)->{data_type});
}

# _have_lob_fields
#
# Arguments: $source, \%fields
#
# Return Value: $yes_no
#
# Returns true if any of %fields are non-empty LOBs.

sub _have_lob_fields {
  my ($self, $source, $fields) = @_;

  for my $col (keys %$fields) {
    if ($self->_is_lob_column($source, $col)) {
      return 1 if defined $fields->{$col} && $fields->{$col} ne '';
    }
  }

  return 0;
}

# _replace_lob_fields
#
# Arguments: $source, \%fields
#
# Return Value: \%lob_fields
#
# Replace LOB fields with L</_empty_lob> values, and return any non-empty ones as
# a hash keyed by field name.

sub _replace_lob_fields {
  my ($self, $source, $fields) = @_;

  my %lob_cols;

  for my $col (keys %$fields) {
    if ($self->_is_lob_column($source, $col)) {
      my $lob_val = delete $fields->{$col};
      if (not defined $lob_val) {
        $fields->{$col} = \'NULL';
      }
      elsif (ref $lob_val && $$lob_val eq ${ $self->_empty_lob($source, $col) })
      {
        # put back, composing class is handling LOBs itself most likely
        $fields->{$col} = $lob_val;
      }
      else {
        $fields->{$col} = $self->_empty_lob($source, $col);
        $lob_cols{$col} = $lob_val unless $lob_val eq '';
      }
    }
  }

  return %lob_cols ? \%lob_cols : undef;
}

# _remove_lob_fields
#
# Arguments: $source, \%fields
#
# Return Value: \%lob_fields
#
# Remove LOB fields from %fields entirely, and return any non-empty ones as a
# hash keyed by field name.

sub _remove_lob_fields {
  my ($self, $source, $fields) = @_;

  my %lob_cols;

  for my $col (keys %$fields) {
    if ($self->_is_lob_column($source, $col)) {
      my $lob_val = delete $fields->{$col};
      if (not defined $lob_val) {
        $fields->{$col} = \'NULL';
      }
      else {
        delete $fields->{$col};
        $lob_cols{$col} = $lob_val unless $lob_val eq '';
      }
    }
  }

  return %lob_cols ? \%lob_cols : undef;
}

# _replace_lob_fields_array
#
# Arguments: $source, \@cols, \@data
#
# Return Value: \@rows_of_lob_values
#
# Like L</_replace_lob_fields> above, but operates on a set of rows in @data
# with @cols as the column names as passed to
# L<DBIx::Class::Storage::DBI/insert_bulk>.
#
# Returns a set of rows of LOB values with the LOBs in the original positions
# they were in @data.

sub _replace_lob_fields_array {
  my ($self, $source, $cols, $data) = @_;

  my @lob_cols;

  for my $i (0..$#$cols) {
    my $col = $cols->[$i];

    if ($self->_is_lob_column($source, $col)) {
      for my $j (0..$#$data) {
        my $lob_val = delete $data->[$j][$i];
        if (not defined $lob_val) {
          $data->[$j][$i] = \'NULL';
        }
        elsif (ref $lob_val && $$lob_val eq ${ $self->_empty_lob($source, $col)})
        {
          # put back, composing class is handling LOBs itself most likely
          $data->[$j][$i] = $lob_val;
        }
        else {
          $data->[$j][$i] = $self->_empty_lob($source, $col);
          $lob_cols[$j][$i] = $lob_val
            unless $lob_val eq '';
        }
      }
    }
  }

  return @lob_cols ? \@lob_cols : undef;
}

# _write_lobs_array
#
# Arguments: $source, \@lobs, \@cols, \@data
#
# Uses the L</_write_lobs> API to write out each row of the @lobs array
# identified by the @data slice.
#
# The @lobs array is as prepared by L</_replace_lob_fields_array> above.

sub _write_lobs_array {
  my ($self, $source, $lobs, $cols, $data) = @_;

  for my $i (0..$#$data) {
    my $datum = $data->[$i];

    my %row;
    @row{@$cols} = @$datum;

    %row = %{ $self->_ident_cond_for_cols($source, \%row) }
      or $self->throw_exception(
        'cannot identify slice for LOB insert '
        . Dumper($datum)
      );

    my %lob_vals;
    for my $j (0..$#$cols) {
      if (exists $lobs->[$i][$j]) {
        $lob_vals{ $cols->[$j] } = $lobs->[$i][$j];
      }
    }

    $self->_write_lobs($source, \%lob_vals, \%row);
  }
}

# Proxy for ResultSource, for overriding in ASE
sub _identifying_column_set {
  my ($self, $source, @args) = @_;
  return $source->_identifying_column_set(@args);
}

# _ident_cond_for_cols
#
# Arguments: $source, \%row
#
# Return Value: \%condition||undef
#
# Attempts to identify %row (as, for example, made by
# L<DBIx::Class::Row/get_columns> or L<DBIx::Class::ResultClass::HashRefInflator>)
# by unique constraints and extract them into the
# %condition that can be used for a select. Returns undef if the %row is
# ambiguous, or there are no unique constraints.
#
# Returns the smallest possible identifying condition, giving preference to the
# primary key.
#
# Uses _identifying_column_set from DBIx::Class::ResultSource.

sub _ident_cond_for_cols {
  my ($self, $source, $row) = @_;

  my $colinfos = $source->columns_info([keys %$row]);

  my $nullable = { map +($_, +{ is_nullable => $colinfos->{$_}{is_nullable} }),
                        keys %$row };

  # Don't skip keys with nullable columns if the column has a defined value in
  # the %row.
  local $colinfos->{$_}{is_nullable} =
    defined $row->{$_} ? 0 : $nullable->{$_} for keys %$row;

  my $cols = $self->_identifying_column_set($source, $colinfos);

  return undef if not $cols;

  return +{ map +($_, $row->{$_}), @$cols };
}

sub insert {
  my $self = shift;

  return $self->next::method(@_) if $self->{_skip_writelobs_impl};

  my ($source, $to_insert) = @_;

  my $lobs = $self->_replace_lob_fields($source, $to_insert);

  return $self->next::method(@_) unless $lobs;

  my $guard = $self->txn_scope_guard;

  my $updated_cols = $self->next::method(@_);

  my $row = { %$to_insert, %$updated_cols };

  my $where = $self->_ident_cond_for_cols($source, $row)
    or $self->throw_exception(
      'Could not identify row for LOB insert '
      . Dumper($row)
    );

  $self->_write_lobs($source, $lobs, $where);

  $guard->commit;

  return $updated_cols;
}

sub update {
  my $self = shift;

  return $self->next::method(@_) if $self->{_skip_writelobs_impl};

  my ($source, $fields, $where, @rest) = @_;

  my $lobs = $self->_remove_lob_fields($source, $fields);

  return $self->next::method(@_) unless $lobs;

  my @key_cols = @{ $self->_identifying_column_set($source) || [] }
    or $self->throw_exception(
         'must be able to uniquely identify rows for LOB updates'
       );

  my $autoinc_supplied_for_op = $self->_autoinc_supplied_for_op;

  $self = $self->_writer_storage if $self->can('_writer_storage'); # for ASE

  local $self->{_autoinc_supplied_for_op} = $autoinc_supplied_for_op
    if $autoinc_supplied_for_op;

  my $guard = $self->txn_scope_guard;

  my ($cursor, @rows);
  {
    local $self->{_autoinc_supplied_for_op} = 0;
    $cursor = $self->select($source, \@key_cols, $where, {});

    if ($self->can('_open_cursors_while_writing_lobs_allowed')
      && (not $self->_open_cursors_while_writing_lobs_allowed)) { # e.g. ASE
      @rows   = $cursor->all;
      $cursor = undef;
    }
  }

  my $count = "0E0";

  while (my $cond = shift @rows
          || ($cursor && do { my @r = $cursor->next; @r && \@r })) {
    $cond = do { my %c; @c{@key_cols} = @$cond; \%c };
    {
      local $self->{_autoinc_supplied_for_op} = 0;
      $self->_write_lobs($source, $lobs, $cond);
    }

    $self->next::method($source, $fields, $cond, @rest) if %$fields;

    $count++;
  }

  $guard->commit;

  return $count;
}

sub insert_bulk {
  my $self = shift;

  return $self->next::method(@_) if $self->{_skip_writelobs_impl};

  my ($source, $cols, $data) = @_;

  my $lobs = $self->_replace_lob_fields_array($source, $cols, $data);

  my $guard = $self->txn_scope_guard;

  $self->next::method(@_);

  $self->_write_lobs_array($source, $lobs, $cols, $data) if $lobs;

  $guard->commit;
}

=head1 AUTHOR

See L<DBIx::Class/AUTHOR> and L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
# vim:sts=2 sw=2:
