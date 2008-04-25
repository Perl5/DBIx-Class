package DBIx::Class::Storage::DBI::Replicated;

use strict;
use warnings;

use DBIx::Class::Storage::DBI;
use DBD::Multi;

use base qw/Class::Accessor::Fast/;

__PACKAGE__->mk_accessors( qw/read_source write_source/ );

=head1 NAME

DBIx::Class::Storage::DBI::Replicated - ALPHA Replicated database support

=head1 SYNOPSIS

The Following example shows how to change an existing $schema to a replicated
storage type and update it's connection information to contain a master DSN and
an array of slaves.

    ## Change storage_type in your schema class
    $schema->storage_type( '::DBI::Replicated' );
    
    ## Set your connection.
    $schema->connect(
        $dsn, $user, $password, {
        	AutoCommit => 1,
        	## Other standard DBI connection or DBD custom attributes added as
        	## usual.  Additionally, we have two custom attributes for defining
        	## slave information and controlling how the underlying DBD::Multi
        	slaves_connect_info => [
        	   ## Define each slave like a 'normal' DBI connection, but you add
        	   ## in a DBD::Multi custom attribute to define how the slave is
        	   ## prioritized.  Please see DBD::Multi for more.
        	   [$slave1dsn, $user, $password, {%slave1opts, priority=>10}],
               [$slave2dsn, $user, $password, {%slave2opts, priority=>10}],
               [$slave3dsn, $user, $password, {%slave3opts, priority=>20}],
               ## add in a preexisting database handle
               [$dbh, '','', {priority=>30}], 
               ## DBD::Multi will call this coderef for connects 
               [sub {  DBI->connect(< DSN info >) }, '', '', {priority=>40}],  
               ## If the last item is hashref, we use that for DBD::Multi's 
               ## configuration information.  Again, see DBD::Multi for more.
               {timeout=>25, failed_max=>2},      	   
        	],
        },
    );
    
    ## Now, just use the schema as normal
    $schema->resultset('Table')->find(< unique >); ## Reads will use slaves
    $schema->resultset('Table')->create(\%info); ## Writes will use master

=head1 DESCRIPTION

Warning: This class is marked ALPHA.  We are using this in development and have
some basic test coverage but the code hasn't yet been stressed by a variety
of databases.  Individual DB's may have quirks we are not aware of.  Please
use this in development and pass along your experiences/bug fixes.

This class implements replicated data store for DBI. Currently you can define
one master and numerous slave database connections. All write-type queries
(INSERT, UPDATE, DELETE and even LAST_INSERT_ID) are routed to master
database, all read-type queries (SELECTs) go to the slave database.

For every slave database you can define a priority value, which controls data
source usage pattern. It uses L<DBD::Multi>, so first the lower priority data
sources used (if they have the same priority, the are used randomized), than
if all low priority data sources fail, higher ones tried in order.

=head1 CONFIGURATION

Please see L<DBD::Multi> for most configuration information.

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

sub _connect_info {
	my $self = shift;
    my $master = $self->write_source->_connect_info;
    $master->[-1]->{slave_connect_info} = $self->read_source->_connect_info;
    return $master;
}

sub connect_info {
	my ($self, $source_info) = @_;

    ## if there is no $source_info, treat this sub like an accessor
    return $self->_connect_info
     if !$source_info;
    
    ## Alright, let's conect the master 
    $self->write_source->connect_info($source_info);
  
    ## Now, build and then connect the Slaves
    my @slaves_connect_info = @{$source_info->[-1]->{slaves_connect_info}};   
    my $dbd_multi_config = ref $slaves_connect_info[-1] eq 'HASH' 
        ? pop @slaves_connect_info : {};

    ## We need to do this since SQL::Abstract::Limit can't guess what DBD::Multi is
    $dbd_multi_config->{limit_dialect} = $self->write_source->sql_maker->limit_dialect
        unless defined $dbd_multi_config->{limit_dialect};

    @slaves_connect_info = map {
        ## if the first element in the arrayhash is a ref, make that the value
        my $db = ref $_->[0] ? $_->[0] : $_;
    	my $priority = $_->[-1]->{priority} || 10; ## default priority is 10
    	$priority => $db;
    } @slaves_connect_info;
    
    $self->read_source->connect_info([ 
        'dbi:Multi:', undef, undef, { 
        	dsns => [@slaves_connect_info],
        	%$dbd_multi_config,
        },
    ]);
    
    ## Return the formated connection information
    return $self->_connect_info;
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

sub limit_dialect { $_->limit_dialect( @_ ) for( shift->all_sources ) }
sub quote_char { $_->quote_char( @_ ) for( shift->all_sources ) }
sub name_sep { $_->quote_char( @_ ) for( shift->all_sources ) }
sub disconnect { $_->disconnect( @_ ) for( shift->all_sources ) }
sub set_schema { $_->set_schema( @_ ) for( shift->all_sources ) }

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
sub txn_do {
    shift->write_source->txn_do( @_ );
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
sub _prep_for_execute {
	shift->write_source->_prep_for_execute(@_);
}

sub debugobj {
	shift->write_source->debugobj(@_);
}
sub debug {
    shift->write_source->debug(@_);
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

John Napiorkowski <john.napiorkowski@takkle.com>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
