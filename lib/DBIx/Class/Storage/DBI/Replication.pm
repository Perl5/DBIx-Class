package DBIx::Class::Storage::DBI::Replication;

use strict;
use warnings;

use DBIx::Class::Storage::DBI;
use DBD::Multi;
use base qw/Class::Accessor::Fast/;

__PACKAGE__->mk_accessors( qw/read_source write_source/ );

=head1 NAME

DBIx::Class::Storage::DBI::Replication - Replicated database support

=head1 SYNOPSIS

  # change storage_type in your schema class
    $schema->storage_type( '::DBI::Replication' );
    $schema->connect_info( [
		     [ "dbi:mysql:database=test;hostname=master", "username", "password", { AutoCommit => 1 } ], # master
		     [ "dbi:mysql:database=test;hostname=slave1", "username", "password", { priority => 10 } ],  # slave1
		     [ "dbi:mysql:database=test;hostname=slave2", "username", "password", { priority => 10 } ],  # slave2
		     <...>
		    ] );
  # If you use LIMIT in your queries (effectively, if you use SQL::Abstract::Limit),
  # do not forget to set up limit_dialect (see: perldoc SQL::Abstract::Limit)
  # DBIC can not set it up automatically, since DBD::Multi could not be supported directly
    $schema->limit_dialect( 'LimitXY' ) # For MySQL

=head1 DESCRIPTION

This class implements replicated data store for DBI. Currently you can define one master and numerous slave database
connections. All write-type queries (INSERT, UPDATE, DELETE and even LAST_INSERT_ID) are routed to master database,
all read-type queries (SELECTs) go to the slave database.

For every slave database you can define a priority value, which controls data source usage pattern. It uses
L<DBD::Multi>, so first the lower priority data sources used (if they have the same priority, the are used
randomized), than if all low priority data sources fail, higher ones tried in order.

=cut

sub new {
    my $proto = shift;
    my $class = ref( $proto ) || $proto;
    my $self = {};

    bless( $self, $class );

    $self->write_source( DBIx::Class::Storage::DBI->new );
    $self->read_source( DBIx::Class::Storage::DBI->new );

    return $self;
}

sub all_sources {
    my $self = shift;

    my @sources = ($self->read_source, $self->write_source);

    return wantarray ? @sources : \@sources;
}

sub connect_info {
    my( $self, $source_info ) = @_;

    $self->write_source->connect_info( $source_info->[0] );

    my @dsns = map { ($_->[3]->{priority} || 10) => $_ } @{$source_info}[1..@$source_info-1];
    $self->read_source->connect_info( [ 'dbi:Multi:', undef, undef, { dsns => \@dsns } ] );
}

sub select {
    shift->read_source->select( @_ );
}
sub select_single {
    shift->read_source->select_single( @_ );
}
sub throw_exception {
    shift->read_source->throw_exception( @_ );
}
sub sql_maker {
    shift->read_source->sql_maker( @_ );
}
sub columns_info_for {
    shift->read_source->columns_info_for( @_ );
}
sub sqlt_type {
    shift->read_source->sqlt_type( @_ );
}
sub create_ddl_dir {
    shift->read_source->create_ddl_dir( @_ );
}
sub deployment_statements {
    shift->read_source->deployment_statements( @_ );
}
sub datetime_parser {
    shift->read_source->datetime_parser( @_ );
}
sub datetime_parser_type {
    shift->read_source->datetime_parser_type( @_ );
}
sub build_datetime_parser {
    shift->read_source->build_datetime_parser( @_ );
}

sub limit_dialect {
    my $self = shift;
    $self->$_->limit_dialect( @_ ) for( $self->all_sources );
}
sub quote_char {
    my $self = shift;
    $self->$_->quote_char( @_ ) for( $self->all_sources );
}
sub name_sep {
    my $self = shift;
    $self->$_->quote_char( @_ ) for( $self->all_sources );
}
sub disconnect {
    my $self = shift;
    $self->$_->disconnect( @_ ) for( $self->all_sources );
}
sub DESTROY {
    my $self = shift;

    undef $self->{write_source};
    undef $self->{read_sources};
}

sub last_insert_id {
    shift->write_source->last_insert_id( @_ );
}
sub insert {
    shift->write_source->insert( @_ );
}
sub update {
    shift->write_source->update( @_ );
}
sub update_all {
    shift->write_source->update_all( @_ );
}
sub delete {
    shift->write_source->delete( @_ );
}
sub delete_all {
    shift->write_source->delete_all( @_ );
}
sub create {
    shift->write_source->create( @_ );
}
sub find_or_create {
    shift->write_source->find_or_create( @_ );
}
sub update_or_create {
    shift->write_source->update_or_create( @_ );
}
sub connected {
    shift->write_source->connected( @_ );
}
sub ensure_connected {
    shift->write_source->ensure_connected( @_ );
}
sub dbh {
    shift->write_source->dbh( @_ );
}
sub txn_begin {
    shift->write_source->txn_begin( @_ );
}
sub txn_commit {
    shift->write_source->txn_commit( @_ );
}
sub txn_rollback {
    shift->write_source->txn_rollback( @_ );
}
sub sth {
    shift->write_source->sth( @_ );
}
sub deploy {
    shift->write_source->deploy( @_ );
}


sub debugfh { shift->_not_supported( 'debugfh' ) };
sub debugcb { shift->_not_supported( 'debugcb' ) };

sub _not_supported {
    my( $self, $method ) = @_;

    die "This Storage does not support $method method.";
}

=head1 SEE ALSO

L<DBI::Class::Storage::DBI>, L<DBD::Multi>, L<DBI>

=head1 AUTHOR

Norbert Csongrádi <bert@cpan.org>

Peter Siklósi <einon@einon.hu>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
