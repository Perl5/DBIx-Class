package DBIx::Class::Admin;

# check deps
BEGIN {
    my @_deps = qw(
        Moose MooseX::Types MooseX::Types::JSON MooseX::Types::Path::Class
        Try::Tiny parent JSON::Any Class::C3::Componentised
        namespace::autoclean
    );

    my @_missing_deps;
    foreach my $dep (@_deps) {
      eval "require $dep";
      if ($@) {
        push @_missing_deps, $dep;
      }
    }

    if (@_missing_deps > 0) {
      die "The following dependecies are missing " . join ",", @_missing_deps;
    }
}

use Moose;
use parent 'DBIx::Class::Schema';
use Carp::Clan qw/^DBIx::Class/;

use MooseX::Types::Moose qw/Int Str Any Bool/;
use DBIx::Class::Admin::Types qw/DBICConnectInfo DBICHashRef/;
use MooseX::Types::JSON qw(JSON);
use MooseX::Types::Path::Class qw(Dir File);
use Try::Tiny;
use JSON::Any qw(DWIW XS JSON);
use namespace::autoclean;

=head1 NAME

DBIx::Class::Admin - Administration object for schemas

=head1 SYNOPSIS

  $ dbicadmin --help

  $ dbicadmin --schema=MyApp::Schema \
    --connect='["dbi:SQLite:my.db", "", ""]' \
    --deploy

  $ dbicadmin --schema=MyApp::Schema --class=Employee \
    --connect='["dbi:SQLite:my.db", "", ""]' \
    --op=update --set='{ "name": "New_Employee" }'

  use DBIx::Class::Admin;

  # ddl manipulation
  my $admin = DBIx::Class::Admin->new(
    schema_class=> 'MY::Schema',
    sql_dir=> $sql_dir,
    connect_info => { dsn => $dsn, user => $user, password => $pass },
  );

  # create SQLite sql
  $admin->create('SQLite');

  # create SQL diff for an upgrade
  $admin->create('SQLite', {} , "1.0");

  # upgrade a database
  $admin->upgrade();

  # install a version for an unversioned schema
  $admin->install("3.0");

=head1 REQUIREMENTS

The following CPAN modules are required to use C<dbicadmin> and this module:

L<Moose>

L<MooseX::Types>

L<MooseX::Types::JSON>

L<MooseX::Types::Path::Class>

L<Try::Tiny>

L<parent>

L<JSON::Any>

(L<JSON::DWIW> preferred for barekey support)

L<namespace::autoclean>

L<Getopt::Long::Descriptive>

L<Text::CSV>

=head1 Attributes

=head2 schema_class

the class of the schema to load

=cut

has 'schema_class' => (
  is    => 'ro',
  isa    => Str,
);


=head2 schema

A pre-connected schema object can be provided for manipulation

=cut

has 'schema' => (
  is      => 'ro',
  isa      => 'DBIx::Class::Schema',
  lazy_build  => 1,
);

sub _build_schema {
  my ($self)  = @_;
  $self->ensure_class_loaded($self->schema_class);

  $self->connect_info->[3]->{ignore_version} =1;
  return $self->schema_class->connect(@{$self->connect_info()} ); # ,  $self->connect_info->[3], { ignore_version => 1} );
}


=head2 resultset

a resultset from the schema to operate on

=cut

has 'resultset' => (
  is      => 'rw',
  isa      => Str,
);


=head2 where

a hash ref or json string to be used for identifying data to manipulate

=cut

has 'where' => (
  is      => 'rw',
  isa      => DBICHashRef,
  coerce    => 1,
);


=head2 set

a hash ref or json string to be used for inserting or updating data

=cut

has 'set' => (
  is      => 'rw',
  isa      => DBICHashRef,
  coerce    => 1,
);


=head2 attrs

a hash ref or json string to be used for passing additonal info to the ->search call

=cut

has 'attrs' => (
  is       => 'rw',
  isa      => DBICHashRef,
  coerce    => 1,
);


=head2 connect_info

connect_info the arguments to provide to the connect call of the schema_class

=cut

has 'connect_info' => (
  is      => 'ro',
  isa      => DBICConnectInfo,
  lazy_build  => 1,
  coerce    => 1,
);

sub _build_connect_info {
  my ($self) = @_;
  return $self->_find_stanza($self->config, $self->config_stanza);
}


=head2 config_file

config_file provide a config_file to read connect_info from, if this is provided
config_stanze should also be provided to locate where the connect_info is in the config
The config file should be in a format readable by Config::General

=cut

has config_file => (
  is      => 'ro',
  isa      => File,
  coerce    => 1,
);


=head2 config_stanza

config_stanza for use with config_file should be a '::' deliminated 'path' to the connection information
designed for use with catalyst config files

=cut

has 'config_stanza' => (
  is      => 'ro',
  isa      => Str,
);


=head2 config

Instead of loading from a file the configuration can be provided directly as a hash ref.  Please note 
config_stanza will still be required.

=cut

has config => (
  is      => 'ro',
  isa      => DBICHashRef,
  lazy_build  => 1,
);

sub _build_config {
  my ($self) = @_;
  try { require Config::Any } catch { $self->throw_exception( "Config::Any is required to parse the config file"); };

  my $cfg = Config::Any->load_files ( {files => [$self->config_file], use_ext =>1, flatten_to_hash=>1});

  # just grab the config from the config file
  $cfg = $cfg->{$self->config_file};
  return $cfg;
}


=head2 sql_dir

The location where sql ddl files should be created or found for an upgrade.

=cut

has 'sql_dir' => (
  is      => 'ro',
  isa      => Dir,
  coerce    => 1,
);


=head2 version

Used for install, the version which will be 'installed' in the schema

=cut

has version => (
  is      => 'rw',
  isa      => Str,
);


=head2 preversion

Previouse version of the schema to create an upgrade diff for, the full sql for that version of the sql must be in the sql_dir

=cut

has preversion => (
  is      => 'rw',
  isa      => Str,
);


=head2 force

Try and force certain operations.

=cut

has force => (
  is      => 'rw',
  isa      => Bool,
);


=head2 quiet

Be less verbose about actions

=cut

has quiet => (
  is      => 'rw',
  isa      => Bool,
);

has '_confirm' => (
  is    => 'bare',
  isa    => Bool,
);


=head1 METHODS

=head2 create

=over 4

=item Arguments: $sqlt_type, \%sqlt_args, $preversion

=back

L<create> will generate sql for the supplied schema_class in sql_dir.  The flavour of sql to 
generate can be controlled by suppling a sqlt_type which should be a L<SQL::Translator> name.  

Arguments for L<SQL::Translator> can be supplied in the sqlt_args hashref.

Optional preversion can be supplied to generate a diff to be used by upgrade.

=cut

sub create {
  my ($self, $sqlt_type, $sqlt_args, $preversion) = @_;

  $preversion ||= $self->preversion();

  my $schema = $self->schema();
  # create the dir if does not exist
  $self->sql_dir->mkpath() if ( ! -d $self->sql_dir);

  $schema->create_ddl_dir( $sqlt_type, (defined $schema->schema_version ? $schema->schema_version : ""), $self->sql_dir->stringify, $preversion, $sqlt_args );
}


=head2 upgrade

=over 4

=item Arguments: <none>

=back

upgrade will attempt to upgrade the connected database to the same version as the schema_class.
B<MAKE SURE YOU BACKUP YOUR DB FIRST>

=cut

sub upgrade {
  my ($self) = @_;
  my $schema = $self->schema();
  if (!$schema->get_db_version()) {
    # schema is unversioned
    $self->throw_exception ("could not determin current schema version, please either install or deploy");
  } else {
    my $ret = $schema->upgrade();
    return $ret;
  }
}


=head2 install

=over 4

=item Arguments: $version

=back

install is here to help when you want to move to L<DBIx::Class::Schema::Versioned> and have an existing 
database.  install will take a version and add the version tracking tables and 'install' the version.  No 
further ddl modification takes place.  Setting the force attribute to a true value will allow overriding of 
already versioned databases.

=cut

sub install {
  my ($self, $version) = @_;

  my $schema = $self->schema();
  $version ||= $self->version();
  if (!$schema->get_db_version() ) {
    # schema is unversioned
    print "Going to install schema version\n";
    my $ret = $schema->install($version);
    print "retun is $ret\n";
  }
  elsif ($schema->get_db_version() and $self->force ) {
    carp "Forcing install may not be a good idea";
    if($self->_confirm() ) {
      $self->schema->_set_db_version({ version => $version});
    }
  }
  else {
    $self->throw_exception ("schema already has a version not installing, try upgrade instead");
  }

}


=head2 deploy

=over 4

=item Arguments: $args

=back

deploy will create the schema at the connected database.  C<$args> are passed straight to 
L<DBIx::Class::Schema/deploy>.

=cut

sub deploy {
  my ($self, $args) = @_;
  my $schema = $self->schema();
  if (!$schema->get_db_version() ) {
    # schema is unversioned
    $schema->deploy( $args, $self->sql_dir)
      or $self->throw_exception ("could not deploy schema");
  } else {
    $self->throw_exception("there already is a database with a version here, try upgrade instead");
  }
}

=head2 insert

=over 4

=item Arguments: $rs, $set

=back

insert takes the name of a resultset from the schema_class and a hashref of data to insert
into that resultset

=cut

sub insert {
  my ($self, $rs, $set) = @_;

  $rs ||= $self->resultset();
  $set ||= $self->set();
  my $resultset = $self->schema->resultset($rs);
  my $obj = $resultset->create( $set );
  print ''.ref($resultset).' ID: '.join(',',$obj->id())."\n" if (!$self->quiet);
}


=head2 update

=over 4

=item Arguments: $rs, $set, $where

=back

update takes the name of a resultset from the schema_class, a hashref of data to update and
a where hash used to form the search for the rows to update.

=cut

sub update {
  my ($self, $rs, $set, $where) = @_;

  $rs ||= $self->resultset();
  $where ||= $self->where();
  $set ||= $self->set();
  my $resultset = $self->schema->resultset($rs);
  $resultset = $resultset->search( ($where||{}) );

  my $count = $resultset->count();
  print "This action will modify $count ".ref($resultset)." records.\n" if (!$self->quiet);

  if ( $self->force || $self->_confirm() ) {
    $resultset->update_all( $set );
  }
}


=head2 delete

=over 4

=item Arguments: $rs, $where, $attrs

=back

delete takes the name of a resultset from the schema_class, a where hashref and a attrs to pass to ->search.
The found data is deleted and cannot be recovered.

=cut

sub delete {
  my ($self, $rs, $where, $attrs) = @_;

  $rs ||= $self->resultset();
  $where ||= $self->where();
  $attrs ||= $self->attrs();
  my $resultset = $self->schema->resultset($rs);
  $resultset = $resultset->search( ($where||{}), ($attrs||()) );

  my $count = $resultset->count();
  print "This action will delete $count ".ref($resultset)." records.\n" if (!$self->quiet);

  if ( $self->force || $self->_confirm() ) {
    $resultset->delete_all();
  }
}


=head2 select

=over 4

=item Arguments: $rs, $where, $attrs

=back

select takes the name of a resultset from the schema_class, a where hashref and a attrs to pass to ->search. 
The found data is returned in a array ref where the first row will be the columns list.

=cut

sub select {
  my ($self, $rs, $where, $attrs) = @_;

  $rs ||= $self->resultset();
  $where ||= $self->where();
  $attrs ||= $self->attrs();
  my $resultset = $self->schema->resultset($rs);
  $resultset = $resultset->search( ($where||{}), ($attrs||()) );

  my @data;
  my @columns = $resultset->result_source->columns();
  push @data, [@columns];# 

  while (my $row = $resultset->next()) {
    my @fields;
    foreach my $column (@columns) {
      push( @fields, $row->get_column($column) );
    }
    push @data, [@fields];
  }

  return \@data;
}

sub _confirm {
  my ($self) = @_;
  print "Are you sure you want to do this? (type YES to confirm) \n";
  # mainly here for testing
  return 1 if ($self->meta->get_attribute('_confirm')->get_value($self));
  my $response = <STDIN>;
  return 1 if ($response=~/^YES/);
  return;
}

sub _find_stanza {
  my ($self, $cfg, $stanza) = @_;
  my @path = split /::/, $stanza;
  while (my $path = shift @path) {
    if (exists $cfg->{$path}) {
      $cfg = $cfg->{$path};
    }
    else {
      $self->throw_exception("could not find $stanza in config, $path did not seem to exist");
    }
  }
  return $cfg;
}

=head1 AUTHOR

See L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself

=cut

1;
