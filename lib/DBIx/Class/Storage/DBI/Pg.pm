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
  my ($self,$source,@cols) = @_;

  return map $self->dbh_do('_dbh_last_insert_id', $source, $_ ), @cols;
}

sub _dbh_last_insert_id {
  my ($self, $dbh, $source, $col ) = @_;

  # if a sequence is defined, explicitly specify it to DBD::Pg's last_insert_id()
  if( my $seq = $source->column_info($col)->{sequence} ) {
      return $dbh->last_insert_id(undef, undef, undef, undef, {sequence => $seq});

  }
  # if not, parse out the schema and table names, pass them to
  # DBD::Pg, and let it figure out (and cache) the sequence name
  # itself.
  else {

    my $schema;
    my $table = $source->name;

    # deref table name if necessary
    $table = $$table if ref $table eq 'SCALAR';

    # parse out schema name if present
    if ( $table =~ /^(.+)\.(.+)$/ ) {
        ( $schema, $table ) = ( $1, $2 );
    }

    return $dbh->last_insert_id( undef, $schema, $table, undef );
  }
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

This driver supports multiple PostgreSQL schemas, with one caveat: for
performance reasons, data about the search path, sequence names, and
so forth is queried as needed and CACHED for subsequent uses.

For this reason, once your schema is instantiated, you should not
change the PostgreSQL schema search path for that schema's database
connection. If you do, Bad Things may happen.

You should do any necessary manipulation of the search path BEFORE
instantiating your schema object, or as part of the on_connect_do
option to connect(), for example:

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
