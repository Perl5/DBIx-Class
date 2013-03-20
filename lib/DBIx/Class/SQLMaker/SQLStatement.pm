package # Hide from PAUSE
   DBIx::Class::SQLMaker::SQLStatement;

use parent 'DBIx::Class::SQLMaker';

# SQL::Statement does not understand
# INSERT INTO $table DEFAULT VALUES
# Adjust SQL here instead
sub insert {  # basically just a copy of the MySQL version...
   my $self = shift;

   if (! $_[1] or (ref $_[1] eq 'HASH' and !keys %{$_[1]} ) ) {
      my $table = $self->_quote($_[0]);
      return "INSERT INTO ${table} (1) VALUES (1)"
   }

   return $self->next::method (@_);
}

# SQL::Statement does not understand
# SELECT ... FOR UPDATE
# Disable it here
sub _lock_select () { '' };

# SQL::Statement hates LIMIT ?, ?
# Change it to a non-bind version
sub _LimitXY {
   my ( $self, $sql, $rs_attrs, $rows, $offset ) = @_;
   $sql .= $self->_parse_rs_attrs( $rs_attrs ) . " LIMIT ";
   $sql .= "$offset, " if +$offset;
   $sql .= $rows;
   return $sql;
}

# SQL::Statement can't handle more than
# one ANSI join, so just convert them all
# to Oracle 8i-style WHERE-clause joins

# (As such, we are stealing globs of code from OracleJoins.pm...)

sub select {
   my ($self, $table, $fields, $where, $rs_attrs, @rest) = @_;

   if (ref $table eq 'ARRAY') {
      # count tables accurately
      my ($cnt, @node) = (0, @$table);
      while (my $tbl = shift @node) {
         my $r = ref $tbl;
         if    ($r eq 'ARRAY') { push(@node, @$tbl); }
         elsif ($r eq 'HASH')  { $cnt++ if ($tbl->{'-rsrc'}); }
      }

      # pull out all join conds as regular WHEREs from all extra tables
      # (but only if we're joining more than 2 tables)
      if ($cnt > 2) {
         $where = $self->_where_joins($where, @{ $table }[ 1 .. $#$table ]);
      }
   }

   return $self->next::method($table, $fields, $where, $rs_attrs, @rest);
}

sub _recurse_from {
   my ($self, $from, @join) = @_;

   # check for a single JOIN
   unless (@join > 1) {
      my $sql = $self->next::method($from, @join);

      # S:S still doesn't like the JOIN X ON ( Y ) syntax with the parens
      $sql =~ s/JOIN (.+) ON \( (.+) \)/JOIN $1 ON $2/;
      return $sql;
   }

   my @sqlf = $self->_from_chunk_to_sql($from);

   for (@join) {
      my ($to, $on) = @$_;

      push (@sqlf, (ref $to eq 'ARRAY') ?
         $self->_recurse_from(@$to) :
         $self->_from_chunk_to_sql($to)
      );
   }

   return join q{, }, @sqlf;
}

sub _where_joins {
   my ($self, $where, @join) = @_;
   my $join_where = $self->_recurse_where_joins(@join);

   if (keys %$join_where) {
      unless (defined $where) { $where = $join_where; }
      else {
         $where = { -or  => $where } if (ref $where eq 'ARRAY');
         $where = { -and => [ $join_where, $where ] };
      }
   }
   return $where;
}

sub _recurse_where_joins {
   my $self = shift;

   my @where;
   foreach my $j (@_) {
      my ($to, $on) = @$j;

      push @where, $self->_recurse_where_joins(@$to) if (ref $to eq 'ARRAY');

      my $join_opts = ref $to eq 'ARRAY' ? $to->[0] : $to;
      if (ref $join_opts eq 'HASH' and my $jt = $join_opts->{-join_type}) {
         # TODO: Figure out a weird way to support ANSI joins and WHERE joins at the same time.
         # (Though, time would be better spent just fixing SQL::Parser to not require this stuff.)

         $self->throw_exception("Can't handle non-inner, non-ANSI joins in SQL::Statement SQL yet!\n")
            if $jt =~ /NATURAL|LEFT|RIGHT|FULL|CROSS|UNION/i;
      }

      # sadly SQLA treats where($scalar) as literal, so we need to jump some hoops
      push @where, map { \sprintf ('%s = %s',
         ref $_        ? $self->_recurse_where($_)        : $self->_quote($_),
         ref $on->{$_} ? $self->_recurse_where($on->{$_}) : $self->_quote($on->{$_}),
      ) } keys %$on;
   }

   return { -and => \@where };
}

1;
