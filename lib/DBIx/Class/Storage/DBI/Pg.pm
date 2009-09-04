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


# get the postgres search path, and cache it
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

  my $sqlmaker = $self->sql_maker;
  local $sqlmaker->{bindtype} = 'normal';

  my ($where, @bind) = $self->sql_maker->where ({
    'a.attnum' => {'>', 0},
    'c.relname' => $table,
    'a.attname' => $col,
    -not_bool => 'a.attisdropped',
    (defined $schema && length $schema)
      ? ( 'n.nspname' => $schema )
      : ( -bool => \'pg_catalog.pg_table_is_visible(c.oid)' )
  });

  my ($seq_expr) = $dbh->selectrow_array(<<EOS,undef,@bind);

SELECT
  (SELECT pg_catalog.pg_get_expr(d.adbin, d.adrelid)
   FROM pg_catalog.pg_attrdef d
   WHERE d.adrelid = a.attrelid AND d.adnum = a.attnum AND a.atthasdef)
FROM pg_catalog.pg_class c
     JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
     JOIN pg_catalog.pg_attribute a ON a.attrelid = c.oid
$where

EOS

  unless (defined $seq_expr && $seq_expr =~ /^nextval\(+'([^']+)'::(?:text|regclass)\)/i ){
    $seq_expr = '' unless defined $seq_expr;
    $self->throw_exception("could not parse sequence expression: '$seq_expr'");
  }

  return $1;
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
