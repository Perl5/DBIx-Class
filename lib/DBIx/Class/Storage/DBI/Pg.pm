package DBIx::Class::Storage::DBI::Pg;

use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI::MultiColumnIn/;
use mro 'c3';

use DBD::Pg qw(:pg_types);

# Ask for a DBD::Pg with array support
warn "DBD::Pg 2.9.2 or greater is strongly recommended\n"
  if ($DBD::Pg::VERSION < 2.009002);  # pg uses (used?) version::qv()

sub with_deferred_fk_checks {
  my ($self, $sub) = @_;

  $self->_get_dbh->do('SET CONSTRAINTS ALL DEFERRED');
  $sub->();
}

sub last_insert_id {
  my ($self,$source,$col) = @_;
  my $seq = ($source->column_info($col)->{sequence} ||= $self->get_autoinc_seq($source,$col))
      or $self->throw_exception( "could not determine sequence for "
                                 . $source->name
                                 . ".$col, please consider adding a "
                                 . "schema-qualified sequence to its column info"
                               );

  $self->_dbh_last_insert_id ($self->_dbh, $seq);
}

# there seems to be absolutely no reason to have this as a separate method,
# but leaving intact in case someone is already overriding it
sub _dbh_last_insert_id {
  my ($self, $dbh, $seq) = @_;
  $dbh->last_insert_id(undef, undef, undef, undef, {sequence => $seq});
}


sub _get_pg_search_path {
    my ($self,$dbh) = @_;
    # cache the search path as ['schema','schema',...] in the storage
    # obj
    $self->{_pg_search_path} ||= do {
        my @search_path;
        my ($sp_string) = $dbh->selectrow_array('SHOW search_path');
        while( $sp_string =~ s/("[^"]+"|[^,]+),?// ) {
            unless( defined $1 and length $1 ) {
                $self->throw_exception("search path sanity check failed: '$1'")
            }
            push @search_path, $1;
        }
        \@search_path
    };
}

sub _dbh_get_autoinc_seq {
  my ($self, $dbh, $schema, $table, $col) = @_;

  # get the list of postgres schemas to search.  if we have a schema
  # specified, use that.  otherwise, use the search path
  my @search_path;
  if( defined $schema and length $schema ) {
      @search_path = ( $schema );
  } else {
      @search_path = @{ $self->_get_pg_search_path($dbh) };
  }

  # find the sequence(s) of the column in question (should have nextval declared on it)
  my @sequence_names;
  foreach my $search_schema (@search_path) {
    my $info = $dbh->column_info(undef,$search_schema,$table,$col)->fetchrow_hashref;
    if($info && defined $info->{COLUMN_DEF}
             && $info->{COLUMN_DEF} =~ /^nextval\(+'([^']+)'::(?:text|regclass)\)/i
    ) {
        push @sequence_names, $1;
    }
  }

  if (@sequence_names != 1) {
    $self->throw_exception (sprintf
      q|Unable to reliably determine autoinc sequence name for '%s'.'%s' (possible candidates: %s)|,
      $table,
      $col,
      join (', ', (@sequence_names ? @sequence_names : 'none found') ),
    );
  }

  my $seq = $sequence_names[0];

  if( $seq !~ /\./ ) {
    my $sth = $dbh->prepare (
      'SELECT * FROM "information_schema"."sequences" WHERE "sequence_name" = ?'
    );
    $sth->execute ($seq);

    my @seen_in_schemas;
    while (my $h = $sth->fetchrow_hashref) {
      push @seen_in_schemas, $h->{sequence_schema};
    }

    if (not @seen_in_schemas) {
      $self->throw_exception (sprintf
        q|Automatically determined autoinc sequence name '%s' for '%s'.'%s' does not seem to exist...'|,
        $seq,
        $table,
        $col,
      );
    }
    elsif (@seen_in_schemas > 1) {
      $self->throw_exception (sprintf
        q|Unable to reliably fully-qualify automatically determined autoinc sequence name '%s' for '%s'.'%s' (same name exist in schemas: %s)|,
        $seq,
        $table,
        $col,
        join (', ', (@seen_in_schemas)),
      );
    }
    else {
      my $sql_maker = $self->sql_maker;
      $seq = join ('.', map { $sql_maker->_quote ($_) } ($seen_in_schemas[0], $seq) );
    }
  }

  return $seq;
}

sub get_autoinc_seq {
  my ($self,$source,$col) = @_;

  my $schema;
  my $table = $source->name;

  if (ref $table eq 'SCALAR') {
    $table = $$table;
  }
  elsif ($table =~ /^(.+)\.(.+)$/) {
    ($schema, $table) = ($1, $2);
  }

  $self->dbh_do('_dbh_get_autoinc_seq', $schema, $table, $col);
}

sub sqlt_type {
  return 'PostgreSQL';
}

sub datetime_parser_type { return "DateTime::Format::Pg"; }

sub bind_attribute_by_data_type {
  my ($self,$data_type) = @_;

  my $bind_attributes = {
    bytea => { pg_type => DBD::Pg::PG_BYTEA },
    blob  => { pg_type => DBD::Pg::PG_BYTEA },
  };

  if( defined $bind_attributes->{$data_type} ) {
    return $bind_attributes->{$data_type};
  }
  else {
    return;
  }
}

sub _sequence_fetch {
  my ( $self, $type, $seq ) = @_;
  my ($id) = $self->_get_dbh->selectrow_array("SELECT nextval('${seq}')");
  return $id;
}

sub _svp_begin {
    my ($self, $name) = @_;

    $self->_get_dbh->pg_savepoint($name);
}

sub _svp_release {
    my ($self, $name) = @_;

    $self->_get_dbh->pg_release($name);
}

sub _svp_rollback {
    my ($self, $name) = @_;

    $self->_get_dbh->pg_rollback_to($name);
}

1;

__END__

=head1 NAME

DBIx::Class::Storage::DBI::Pg - Automatic primary key class for PostgreSQL

=head1 SYNOPSIS

  # In your table classes
  __PACKAGE__->load_components(qw/PK::Auto Core/);
  __PACKAGE__->set_primary_key('id');
  __PACKAGE__->sequence('mysequence');

=head1 DESCRIPTION

This class implements autoincrements for PostgreSQL.

=head1 POSTGRESQL SCHEMA SUPPORT

This supports multiple PostgreSQL schemas, with one caveat: for
performance reasons, the schema search path is queried the first time it is
needed and CACHED for subsequent uses.

For this reason, you should do any necessary manipulation of the
PostgreSQL search path BEFORE instantiating your schema object, or as
part of the on_connect_do option to connect(), for example:

   my $schema = My::Schema->connect
                  ( $dsn,$user,$pass,
                    { on_connect_do =>
                        [ 'SET search_path TO myschema, foo, public' ],
                    },
                  );

=head1 AUTHORS

See L<DBIx::Class/CONTRIBUTORS>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
