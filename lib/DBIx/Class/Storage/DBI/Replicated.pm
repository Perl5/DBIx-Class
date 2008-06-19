package DBIx::Class::Storage::DBI::Replicated;

use Moose;
use Class::MOP;
use Moose::Util::TypeConstraints;
use DBIx::Class::Storage::DBI;
use DBIx::Class::Storage::DBI::Replicated::Pool;
use DBIx::Class::Storage::DBI::Replicated::Balancer;

=head1 NAME

DBIx::Class::Storage::DBI::Replicated - ALPHA Replicated database support

=head1 SYNOPSIS

The Following example shows how to change an existing $schema to a replicated
storage type, add some replicated (readonly) databases, and perform reporting
tasks.

  ## Change storage_type in your schema class
  $schema->storage_type( ['::DBI::Replicated', {balancer=>'::Random'}] );
  
  ## Add some slaves.  Basically this is an array of arrayrefs, where each
  ## arrayref is database connect information
  
  $schema->storage->connect_replicants(
    [$dsn1, $user, $pass, \%opts],
    [$dsn2, $user, $pass, \%opts],
    [$dsn3, $user, $pass, \%opts],
  );
  
=head1 DESCRIPTION

Warning: This class is marked ALPHA.  We are using this in development and have
some basic test coverage but the code hasn't yet been stressed by a variety
of databases.  Individual DB's may have quirks we are not aware of.  Please
use this in development and pass along your experiences/bug fixes.

This class implements replicated data store for DBI. Currently you can define
one master and numerous slave database connections. All write-type queries
(INSERT, UPDATE, DELETE and even LAST_INSERT_ID) are routed to master
database, all read-type queries (SELECTs) go to the slave database.

Basically, any method request that L<DBIx::Class::Storage::DBI> would normally
handle gets delegated to one of the two attributes: L</read_handler> or to
L</write_handler>.  Additionally, some methods need to be distributed
to all existing storages.  This way our storage class is a drop in replacement
for L<DBIx::Class::Storage::DBI>.

Read traffic is spread across the replicants (slaves) occuring to a user
selected algorithm.  The default algorithm is random weighted.

=head1 NOTES

The consistancy betweeen master and replicants is database specific.  The Pool
gives you a method to validate it's replicants, removing and replacing them
when they fail/pass predefined criteria.  It is recommened that your application
define two schemas, one using the replicated storage and another that just 
connects to the master.

=head1 ATTRIBUTES

This class defines the following attributes.

=head2 schema

The underlying L<DBIx::Class::Schema> object this storage is attaching

=cut

has 'schema' => (
    is=>'rw',
    isa=>'DBIx::Class::Schema',
    weak_ref=>1,
    required=>1,
);

=head2 pool_type

Contains the classname which will instantiate the L</pool> object.  Defaults 
to: L<DBIx::Class::Storage::DBI::Replicated::Pool>.

=cut

has 'pool_type' => (
  is=>'ro',
  isa=>'ClassName',
  required=>1,
  default=>'DBIx::Class::Storage::DBI::Replicated::Pool',
  handles=>{
    'create_pool' => 'new',
  },
);

=head2 pool_args

Contains a hashref of initialized information to pass to the Balancer object.
See L<DBIx::Class::Storage::Replicated::Pool> for available arguments.

=cut

has 'pool_args' => (
  is=>'ro',
  isa=>'HashRef',
  lazy=>1,
  required=>1,
  default=>sub { {} },
);


=head2 balancer_type

The replication pool requires a balance class to provider the methods for
choose how to spread the query load across each replicant in the pool.

=cut

subtype 'DBIx::Class::Storage::DBI::Replicated::BalancerClassNamePart',
  as 'ClassName';
    
coerce 'DBIx::Class::Storage::DBI::Replicated::BalancerClassNamePart',
  from 'Str',
  via {
  	my $type = $_;
    if($type=~m/^::/) {
      $type = 'DBIx::Class::Storage::DBI::Replicated::Balancer'.$type;
    }  
    Class::MOP::load_class($type);  
    $type;  	
  };

has 'balancer_type' => (
  is=>'ro',
  isa=>'DBIx::Class::Storage::DBI::Replicated::BalancerClassNamePart',
  coerce=>1,
  required=>1,
  default=> 'DBIx::Class::Storage::DBI::Replicated::Balancer::First',
  handles=>{
    'create_balancer' => 'new',
  },
);

=head2 balancer_args

Contains a hashref of initialized information to pass to the Balancer object.
See L<DBIx::Class::Storage::Replicated::Balancer> for available arguments.

=cut

has 'balancer_args' => (
  is=>'ro',
  isa=>'HashRef',
  lazy=>1,
  required=>1,
  default=>sub { {} },
);

=head2 pool

Is a <DBIx::Class::Storage::DBI::Replicated::Pool> or derived class.  This is a
container class for one or more replicated databases.

=cut

has 'pool' => (
  is=>'ro',
  isa=>'DBIx::Class::Storage::DBI::Replicated::Pool',
  lazy_build=>1,
  handles=>[qw/
    connect_replicants    
    replicants
    has_replicants
  /],
);

=head2 balancer

Is a <DBIx::Class::Storage::DBI::Replicated::Balancer> or derived class.  This 
is a class that takes a pool (<DBIx::Class::Storage::DBI::Replicated::Pool>)

=cut

has 'balancer' => (
  is=>'ro',
  isa=>'DBIx::Class::Storage::DBI::Replicated::Balancer',
  lazy_build=>1,
  handles=>[qw/auto_validate_every/],
);

=head2 master

The master defines the canonical state for a pool of connected databases.  All
the replicants are expected to match this databases state.  Thus, in a classic
Master / Slaves distributed system, all the slaves are expected to replicate
the Master's state as quick as possible.  This is the only database in the
pool of databases that is allowed to handle write traffic.

=cut

has 'master' => (
  is=> 'ro',
  isa=>'DBIx::Class::Storage::DBI',
  lazy_build=>1,
);

=head1 ATTRIBUTES IMPLEMENTING THE DBIx::Storage::DBI INTERFACE

The following methods are delegated all the methods required for the 
L<DBIx::Class::Storage::DBI> interface.

=head2 read_handler

Defines an object that implements the read side of L<BIx::Class::Storage::DBI>.

=cut

has 'read_handler' => (
  is=>'rw',
  isa=>'Object',
  lazy_build=>1,
  handles=>[qw/
    select
    select_single
    columns_info_for
  /],    
);

=head2 write_handler

Defines an object that implements the write side of L<BIx::Class::Storage::DBI>.

=cut

has 'write_handler' => (
  is=>'ro',
  isa=>'Object',
  lazy_build=>1,
  lazy_build=>1,
  handles=>[qw/   
    on_connect_do
    on_disconnect_do       
    connect_info
    throw_exception
    sql_maker
    sqlt_type
    create_ddl_dir
    deployment_statements
    datetime_parser
    datetime_parser_type        
    last_insert_id
    insert
    insert_bulk
    update
    delete
    dbh
    txn_begin
    txn_do
    txn_commit
    txn_rollback
    txn_scope_guard
    sth
    deploy

    reload_row
    _prep_for_execute
    configure_sqlt
    
  /],
);

=head1 METHODS

This class defines the following methods.

=head2 new

L<DBIx::Class::Schema> when instantiating it's storage passed itself as the
first argument.  So we need to massage the arguments a bit so that all the
bits get put into the correct places.

=cut

around 'new' => sub {
  my ($new, $self, $schema, $storage_type_args, @args) = @_;
  return $self->$new(schema=>$schema, %$storage_type_args, @args);
};

=head2 _build_master

Lazy builder for the L</master> attribute.

=cut

sub _build_master {
  my $self = shift @_;
  DBIx::Class::Storage::DBI->new($self->schema);
}

=head2 _build_pool

Lazy builder for the L</pool> attribute.

=cut

sub _build_pool {
  my $self = shift @_;
  $self->create_pool(%{$self->pool_args});
}

=head2 _build_balancer

Lazy builder for the L</balancer> attribute.  This takes a Pool object so that
the balancer knows which pool it's balancing.

=cut

sub _build_balancer {
  my $self = shift @_;
  $self->create_balancer(
    pool=>$self->pool, 
    master=>$self->master,
    %{$self->balancer_args},
  );
}

=head2 _build_write_handler

Lazy builder for the L</write_handler> attribute.  The default is to set this to
the L</master>.

=cut

sub _build_write_handler {
  return shift->master;
}

=head2 _build_read_handler

Lazy builder for the L</read_handler> attribute.  The default is to set this to
the L</balancer>.

=cut

sub _build_read_handler {
  return shift->balancer;
}

=head2 around: connect_replicants

All calls to connect_replicants needs to have an existing $schema tacked onto
top of the args, since L<DBIx::Storage::DBI> needs it.

=cut

around 'connect_replicants' => sub {
  my ($method, $self, @args) = @_;
  $self->$method($self->schema, @args);
};

=head2 all_storages

Returns an array of of all the connected storage backends.  The first element
in the returned array is the master, and the remainings are each of the
replicants.

=cut

sub all_storages {
  my $self = shift @_;
  return grep {defined $_ && blessed $_} (
     $self->master,
     $self->replicants,
  );
}

=head2 execute_reliably ($coderef, ?@args)

Given a coderef, saves the current state of the L</read_handler>, forces it to
use reliable storage (ie sets it to the master), executes a coderef and then
restores the original state.

Example:

  my $reliably = sub {
    my $name = shift @_;
    $schema->resultset('User')->create({name=>$name});
    my $user_rs = $schema->resultset('User')->find({name=>$name}); 
    return $user_rs;
  };

  my $user_rs = $schema->storage->execute_reliably($reliably, 'John');

Use this when you must be certain of your database state, such as when you just
inserted something and need to get a resultset including it, etc.

=cut

sub execute_reliably {
  my ($self, $coderef, @args) = @_;
  
  unless( ref $coderef eq 'CODE') {
    $self->throw_exception('Second argument must be a coderef');
  }
  
  ##Get copy of master storage
  my $master = $self->master;
  
  ##Get whatever the current read hander is
  my $current = $self->read_handler;
  
  ##Set the read handler to master
  $self->read_handler($master);
  
  ## do whatever the caller needs
  my @result;
  my $want_array = wantarray;
  
  eval {
    if($want_array) {
      @result = $coderef->(@args);
    } elsif(defined $want_array) {
      ($result[0]) = ($coderef->(@args));
    } else {
      $coderef->(@args);
    }       
  };
  
  ##Reset to the original state
  $self->read_handler($current); 
  
  ##Exception testing has to come last, otherwise you might leave the 
  ##read_handler set to master.
  
  if($@) {
    $self->throw_exception("coderef returned an error: $@");
  } else {
    return $want_array ? @result : $result[0];
  }
}

=head2 set_reliable_storage

Sets the current $schema to be 'reliable', that is all queries, both read and
write are sent to the master
  
=cut

sub set_reliable_storage {
  my $self = shift @_;
  my $schema = $self->schema;
  my $write_handler = $self->schema->storage->write_handler;
  
  $schema->storage->read_handler($write_handler);
}

=head2 set_balanced_storage

Sets the current $schema to be use the </balancer> for all reads, while all
writea are sent to the master only
  
=cut

sub set_balanced_storage {
  my $self = shift @_;
  my $schema = $self->schema;
  my $write_handler = $self->schema->storage->balancer;
  
  $schema->storage->read_handler($write_handler);
}

=head2 around: txn_do ($coderef)

Overload to the txn_do method, which is delegated to whatever the
L<write_handler> is set to.  We overload this in order to wrap in inside a
L</execute_reliably> method.

=cut

around 'txn_do' => sub {
  my($txn_do, $self, $coderef, @args) = @_;
  $self->execute_reliably(sub {$self->$txn_do($coderef, @args)}); 
};

=head2 connected

Check that the master and at least one of the replicants is connected.

=cut

sub connected {
  my $self = shift @_;
  return
    $self->master->connected &&
    $self->pool->connected_replicants;
}

=head2 ensure_connected

Make sure all the storages are connected.

=cut

sub ensure_connected {
  my $self = shift @_;
  foreach my $source ($self->all_storages) {
    $source->ensure_connected(@_);
  }
}

=head2 limit_dialect

Set the limit_dialect for all existing storages

=cut

sub limit_dialect {
  my $self = shift @_;
  foreach my $source ($self->all_storages) {
    $source->limit_dialect(@_);
  }
}

=head2 quote_char

Set the quote_char for all existing storages

=cut

sub quote_char {
  my $self = shift @_;
  foreach my $source ($self->all_storages) {
    $source->quote_char(@_);
  }
}

=head2 name_sep

Set the name_sep for all existing storages

=cut

sub name_sep {
  my $self = shift @_;
  foreach my $source ($self->all_storages) {
    $source->name_sep(@_);
  }
}

=head2 set_schema

Set the schema object for all existing storages

=cut

sub set_schema {
  my $self = shift @_;
  foreach my $source ($self->all_storages) {
    $source->set_schema(@_);
  }
}

=head2 debug

set a debug flag across all storages

=cut

sub debug {
  my $self = shift @_;
  foreach my $source ($self->all_storages) {
    $source->debug(@_);
  }
}

=head2 debugobj

set a debug object across all storages

=cut

sub debugobj {
  my $self = shift @_;
  foreach my $source ($self->all_storages) {
    $source->debugobj(@_);
  }
}

=head2 debugfh

set a debugfh object across all storages

=cut

sub debugfh {
  my $self = shift @_;
  foreach my $source ($self->all_storages) {
    $source->debugfh(@_);
  }
}

=head2 debugcb

set a debug callback across all storages

=cut

sub debugcb {
  my $self = shift @_;
  foreach my $source ($self->all_storages) {
    $source->debugcb(@_);
  }
}

=head2 disconnect

disconnect everything

=cut

sub disconnect {
  my $self = shift @_;
  foreach my $source ($self->all_storages) {
    $source->disconnect(@_);
  }
}

=head1 AUTHOR

  John Napiorkowski <john.napiorkowski@takkle.com>

Based on code originated by:

  Norbert Csongrádi <bert@cpan.org>
  Peter Siklósi <einon@einon.hu>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
