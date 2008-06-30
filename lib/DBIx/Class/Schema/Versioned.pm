package # Hide from PAUSE
  DBIx::Class::Version::Table;
use base 'DBIx::Class';
use strict;
use warnings;

__PACKAGE__->load_components(qw/ Core/);
__PACKAGE__->table('dbix_class_schema_versions');

__PACKAGE__->add_columns
    ( 'version' => {
        'data_type' => 'VARCHAR',
        'is_auto_increment' => 0,
        'default_value' => undef,
        'is_foreign_key' => 0,
        'name' => 'version',
        'is_nullable' => 0,
        'size' => '10'
        },
      'installed' => {
          'data_type' => 'VARCHAR',
          'is_auto_increment' => 0,
          'default_value' => undef,
          'is_foreign_key' => 0,
          'name' => 'installed',
          'is_nullable' => 0,
          'size' => '20'
          },
      );
__PACKAGE__->set_primary_key('version');

package # Hide from PAUSE
  DBIx::Class::Version::TableCompat;
use base 'DBIx::Class';
__PACKAGE__->load_components(qw/ Core/);
__PACKAGE__->table('SchemaVersions');

__PACKAGE__->add_columns
    ( 'Version' => {
        'data_type' => 'VARCHAR',
        },
      'Installed' => {
          'data_type' => 'VARCHAR',
          },
      );
__PACKAGE__->set_primary_key('Version');

package # Hide from PAUSE
  DBIx::Class::Version;
use base 'DBIx::Class::Schema';
use strict;
use warnings;

__PACKAGE__->register_class('Table', 'DBIx::Class::Version::Table');

package # Hide from PAUSE
  DBIx::Class::VersionCompat;
use base 'DBIx::Class::Schema';
use strict;
use warnings;

__PACKAGE__->register_class('TableCompat', 'DBIx::Class::Version::TableCompat');


# ---------------------------------------------------------------------------

=head1 NAME

DBIx::Class::Schema::Versioned - DBIx::Class::Schema plugin for Schema upgrades

=head1 SYNOPSIS

  package Library::Schema;
  use base qw/DBIx::Class::Schema/;   
  # load Library::Schema::CD, Library::Schema::Book, Library::Schema::DVD
  __PACKAGE__->load_classes(qw/CD Book DVD/);

  __PACKAGE__->load_components(qw/+DBIx::Class::Schema::Versioned/);
  __PACKAGE__->upgrade_directory('/path/to/upgrades/');
  __PACKAGE__->backup_directory('/path/to/backups/');


=head1 DESCRIPTION

This module is a component designed to extend L<DBIx::Class::Schema>
classes, to enable them to upgrade to newer schema layouts. To use this
module, you need to have called C<create_ddl_dir> on your Schema to
create your upgrade files to include with your delivery.

A table called I<dbix_class_schema_versions> is created and maintained by the
module. This contains two fields, 'Version' and 'Installed', which
contain each VERSION of your Schema, and the date+time it was installed.

The actual upgrade is called manually by calling C<upgrade> on your
schema object. Code is run at connect time to determine whether an
upgrade is needed, if so, a warning "Versions out of sync" is
produced.

So you'll probably want to write a script which generates your DDLs and diffs
and another which executes the upgrade.

NB: At the moment, only SQLite and MySQL are supported. This is due to
spotty behaviour in the SQL::Translator producers, please help us by
them.

=head1 METHODS

=head2 upgrade_directory

Use this to set the directory your upgrade files are stored in.

=head2 backup_directory

Use this to set the directory you want your backups stored in.

=cut

package DBIx::Class::Schema::Versioned;

use strict;
use warnings;
use base 'DBIx::Class';
use POSIX 'strftime';
use Data::Dumper;

__PACKAGE__->mk_classdata('_filedata');
__PACKAGE__->mk_classdata('upgrade_directory');
__PACKAGE__->mk_classdata('backup_directory');
__PACKAGE__->mk_classdata('do_backup');
__PACKAGE__->mk_classdata('do_diff_on_init');

=head2 schema_version

Returns the current schema class' $VERSION; does -not- use $schema->VERSION
since that varies in results depending on if version.pm is installed, and if
so the perl or XS versions. If you want this to change, bug the version.pm
author to make vpp and vxs behave the same.

=cut

sub schema_version {
  my ($self) = @_;
  my $class = ref($self)||$self;
  my $version;
  {
    no strict 'refs';
    $version = ${"${class}::VERSION"};
  }
  return $version;
}

=head2 get_db_version

Returns the version that your database is currently at. This is determined by the values in the
dbix_class_schema_versions table that $self->upgrade writes to.

=cut

sub get_db_version
{
    my ($self, $rs) = @_;

    my $vtable = $self->{vschema}->resultset('Table');
    my $version = 0;
    eval {
      my $stamp = $vtable->get_column('installed')->max;
      $version = $vtable->search({ installed => $stamp })->first->version;
    };
    return $version;
}

sub _source_exists
{
    my ($self, $rs) = @_;

    my $c = eval {
        $rs->search({ 1, 0 })->count;
    };
    return 0 if $@ || !defined $c;

    return 1;
}

=head2 backup

This is an overwritable method which is called just before the upgrade, to
allow you to make a backup of the database. Per default this method attempts
to call C<< $self->storage->backup >>, to run the standard backup on each
database type. 

This method should return the name of the backup file, if appropriate..

This method is disabled by default. Set $schema->do_backup(1) to enable it.

=cut

sub backup
{
    my ($self) = @_;
    ## Make each ::DBI::Foo do this
    $self->storage->backup($self->backup_directory());
}

# is this just a waste of time? if not then merge with DBI.pm
sub _create_db_to_schema_diff {
  my $self = shift;

  my %driver_to_db_map = (
                          'mysql' => 'MySQL'
                         );

  my $db = $driver_to_db_map{$self->storage->dbh->{Driver}->{Name}};
  unless ($db) {
    print "Sorry, this is an unsupported DB\n";
    return;
  }

  eval 'require SQL::Translator "0.09"';
  if ($@) {
    $self->throw_exception("SQL::Translator 0.09 required");
  }

  my $db_tr = SQL::Translator->new({ 
                                    add_drop_table => 1, 
                                    parser => 'DBI',
                                    parser_args => { dbh => $self->storage->dbh }
                                   });

  $db_tr->producer($db);
  my $dbic_tr = SQL::Translator->new;
  $dbic_tr->parser('SQL::Translator::Parser::DBIx::Class');
  $dbic_tr = $self->storage->configure_sqlt($dbic_tr, $db);
  $dbic_tr->data($self);
  $dbic_tr->producer($db);

  $db_tr->schema->name('db_schema');
  $dbic_tr->schema->name('dbic_schema');

  # is this really necessary?
  foreach my $tr ($db_tr, $dbic_tr) {
    my $data = $tr->data;
    $tr->parser->($tr, $$data);
  }

  my $diff = SQL::Translator::Diff::schema_diff($db_tr->schema, $db, 
                                                $dbic_tr->schema, $db,
                                                { ignore_constraint_names => 1, ignore_index_names => 1, caseopt => 1 });

  my $filename = $self->ddl_filename(
                                         $db,
                                         $self->upgrade_directory,
                                         $self->schema_version,
                                         'PRE',
                                    );
  my $file;
  if(!open($file, ">$filename"))
    {
      $self->throw_exception("Can't open $filename for writing ($!)");
      next;
    }
  print $file $diff;
  close($file);

  print "WARNING: There may be differences between your DB and your DBIC schema. Please review and if necessary run the SQL in $filename to sync your DB.\n";
}

=head2 upgrade

Call this to attempt to upgrade your database from the version it is at to the version
this DBIC schema is at. 

It requires an SQL diff file to exist in $schema->upgrade_directory, normally you will
have created this using $schema->create_ddl_dir.

=cut

sub upgrade
{
  my ($self) = @_;
  my $db_version = $self->get_db_version();

  # db unversioned
  unless ($db_version) {
    # set version in dbix_class_schema_versions table, can't actually upgrade as we don 't know what version the DB is at
    $self->_create_db_to_schema_diff() if ($self->do_diff_on_init);

    # create versions table and version row
    $self->{vschema}->deploy;
    $self->_set_db_version;
    return;
  }

  # db and schema at same version. do nothing
  if ($db_version eq $self->schema_version) {
    print "Upgrade not necessary\n";
    return;
  }

  # strangely the first time this is called can
  # differ to subsequent times. so we call it 
  # here to be sure.
  # XXX - just fix it
  $self->storage->sqlt_type;
  
  my $upgrade_file = $self->ddl_filename(
                                         $self->storage->sqlt_type,
                                         $self->upgrade_directory,
                                         $self->schema_version,
                                         $db_version,
                                        );

  unless (-f $upgrade_file) {
    warn "Upgrade not possible, no upgrade file found ($upgrade_file), please create one\n";
    return;
  }

  # backup if necessary then apply upgrade
  $self->_filedata($self->_read_sql_file($upgrade_file));
  $self->backup() if($self->do_backup);
  $self->txn_do(sub { $self->do_upgrade() });

  # set row in dbix_class_schema_versions table
  $self->_set_db_version;
}

sub _set_db_version {
  my $self = shift;

  my $vtable = $self->{vschema}->resultset('Table');
  $vtable->create({ version => $self->schema_version,
                      installed => strftime("%Y-%m-%d %H:%M:%S", gmtime())
                      });

}

sub _read_sql_file {
  my $self = shift;
  my $file = shift || return;

  my $fh;
  open $fh, "<$file" or warn("Can't open upgrade file, $file ($!)");
  my @data = split(/\n/, join('', <$fh>));
  @data = grep(!/^--/, @data);
  @data = split(/;/, join('', @data));
  close($fh);
  @data = grep { $_ && $_ !~ /^-- / } @data;
  @data = grep { $_ !~ /^(BEGIN TRANSACTION|COMMIT)/m } @data;
  return \@data;
}

=head2 do_upgrade

This is an overwritable method used to run your upgrade. The freeform method
allows you to run your upgrade any way you please, you can call C<run_upgrade>
any number of times to run the actual SQL commands, and in between you can
sandwich your data upgrading. For example, first run all the B<CREATE>
commands, then migrate your data from old to new tables/formats, then 
issue the DROP commands when you are finished. Will run the whole file as it is by default.

=cut

sub do_upgrade
{
  my ($self) = @_;

  # just run all the commands (including inserts) in order                                                        
  $self->run_upgrade(qr/.*?/);
}

=head2 run_upgrade

 $self->run_upgrade(qr/create/i);

Runs a set of SQL statements matching a passed in regular expression. The
idea is that this method can be called any number of times from your
C<upgrade> method, running whichever commands you specify via the
regex in the parameter. Probably won't work unless called from the overridable
do_upgrade method.

=cut

sub run_upgrade
{
    my ($self, $stm) = @_;

    return unless ($self->_filedata);
    my @statements = grep { $_ =~ $stm } @{$self->_filedata};
    $self->_filedata([ grep { $_ !~ /$stm/i } @{$self->_filedata} ]);

    for (@statements)
    {      
        $self->storage->debugobj->query_start($_) if $self->storage->debug;
        $self->storage->dbh->do($_) or warn "SQL was:\n $_";
        $self->storage->debugobj->query_end($_) if $self->storage->debug;
    }

    return 1;
}

=head2 connection

Overloaded method. This checks the DBIC schema version against the DB version and
warns if they are not the same or if the DB is unversioned. It also provides
compatibility between the old versions table (SchemaVersions) and the new one
(dbix_class_schema_versions).

To avoid the checks on connect, set the env var DBIC_NO_VERSION_CHECK or alternatively you can set the ignore_version attr in the forth arg like so:

  my $schema = MyApp::Schema->connect(
    $dsn,
    $user,
    $password,
    { ignore_version => 1 },
  );

=cut

sub connection {
  my $self = shift;
  $self->next::method(@_);
  $self->_on_connect($_[3]);
  return $self;
}

sub _on_connect
{
  my ($self, $args) = @_;

  $args = {} unless $args;
  $self->{vschema} = DBIx::Class::Version->connect(@{$self->storage->connect_info()});
  my $vtable = $self->{vschema}->resultset('Table');

  # check for legacy versions table and move to new if exists
  my $vschema_compat = DBIx::Class::VersionCompat->connect(@{$self->storage->connect_info()});
  unless ($self->_source_exists($vtable)) {
    my $vtable_compat = $vschema_compat->resultset('TableCompat');
    if ($self->_source_exists($vtable_compat)) {
      $self->{vschema}->deploy;
      map { $vtable->create({ installed => $_->Installed, version => $_->Version }) } $vtable_compat->all;
      $self->storage->dbh->do("DROP TABLE " . $vtable_compat->result_source->from);
    }
  }

  # useful when connecting from scripts etc
  return if ($args->{ignore_version} || ($ENV{DBIC_NO_VERSION_CHECK} && !exists $args->{ignore_version}));
  
  my $pversion = $self->get_db_version();

  if($pversion eq $self->schema_version)
    {
#         warn "This version is already installed\n";
        return 1;
    }

  if(!$pversion)
    {
        warn "Your DB is currently unversioned. Please call upgrade on your schema to sync the DB.\n";
        return 1;
    }

  warn "Versions out of sync. This is " . $self->schema_version . 
    ", your database contains version $pversion, please call upgrade on your Schema.\n";
}

1;


=head1 AUTHORS

Jess Robinson <castaway@desert-island.demon.co.uk>
Luke Saunders <luke@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.
