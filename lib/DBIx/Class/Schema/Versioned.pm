package DBIx::Class::Version::Table;
use base 'DBIx::Class';
use strict;
use warnings;

__PACKAGE__->load_components(qw/ Core/);
__PACKAGE__->table('SchemaVersions');

__PACKAGE__->add_columns(
      'Version' => {
          'data_type' => 'VARCHAR',
          'is_auto_increment' => 0,
          'default_value' => undef,
          'is_foreign_key' => 0,
          'name' => 'Version',
          'is_nullable' => 0,
          'size' => '10'
      },
      'Installed' => {
          'data_type' => 'VARCHAR',
          'is_auto_increment' => 0,
          'default_value' => undef,
          'is_foreign_key' => 0,
          'name' => 'Installed',
          'is_nullable' => 0,
          'size' => '20'
      },
);
__PACKAGE__->set_primary_key('Version');

package DBIx::Class::Version;
use base 'DBIx::Class::Schema';
use strict;
use warnings;

__PACKAGE__->register_class('Table', 'DBIx::Class::Version::Table');


# ---------------------------------------------------------------------------
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

sub connection {
  my $self = shift;
  $self->next::method(@_);
  $self->_on_connect;
  return $self;
}

sub _on_connect
{
    my ($self) = @_;
    $self->{vschema} = DBIx::Class::Version->connect(@{$self->storage->connect_info()});

    my $pversion = $self->get_db_version();

    if($pversion eq $self->schema_version)
    {
        warn "This version is already installed\n";
        return 1;
    }

    if(!$pversion)
    {
        warn "Your DB is currently unversioned. Please call upgrade on your schema to sync the DB.\n";
        return 1;
    }

    my $file = $self->ddl_filename(
                                   $self->storage->sqlt_type,
                                   $self->upgrade_directory,
                                   $self->schema_version
                                   );
    if(!$file)
    {
        # No upgrade path between these two versions
        return 1;
    }


    ## Don't do this yet, do only on command?
    ## If we do this later, where does the Version table get updated??
    warn "Versions out of sync. This is " . $self->schema_version . 
        ", your database contains version $pversion, please call upgrade on your Schema.\n";
}

sub get_db_version
{
    my ($self, $rs) = @_;

    my $vtable = $self->{vschema}->resultset('Table');
    return 0 unless ($self->_source_exists($vtable));

    my $psearch = $vtable->search(undef, 
                                    { select => [
                                                 { 'max' => 'Installed' },
                                                 ],
                                          as => ['maxinstall'],
                                      })->first;
    my $pversion = $vtable->search({ Installed => $psearch->get_column('maxinstall'),
                                })->first;
    $pversion = $pversion->Version if($pversion);
    return $pversion;
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

sub backup
{
    my ($self) = @_;
    ## Make each ::DBI::Foo do this
    $self->storage->backup($self->backup_directory());
}

# TODO: some of this needs to be merged with ->create_ddl_dir
sub upgrade
{
    my ($self) = @_;
    my $db_version = $self->get_db_version();

    my %driver_to_db_map = (
                            'mysql' => 'MySQL'
                           );
    if (!$db_version) {
      my $db = $driver_to_db_map{$self->storage->dbh->{Driver}->{Name}};
      unless ($db) {
        print "Sorry, this is an unsupported DB\n";
        return;
      }

      require SQL::Translator;
      require SQL::Translator::Diff;
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
                                                    { caseopt => 1 });

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

      # create versions table
      $self->{vschema}->deploy;

      print "WARNING: There may be differences between your DB and your DBIC schema. Please review and if necessary run the SQL in $filename to sync your DB.\n";
    } else {
      if ($db_version eq $self->schema_version) {
        print "Upgrade not necessary\n";
        return;
      }

      my $file = $self->ddl_filename(
                                 $self->storage->sqlt_type,
                                 $self->upgrade_directory,
                                 $self->schema_version,
                                 $db_version,
                                 );

      if(!-f $file)
      {
         warn "Upgrade not possible, no upgrade file found ($file)\n";
         return;
      }

      my $fh;
      open $fh, "<$file" or warn("Can't open upgrade file, $file ($!)");
      my @data = split(/\n/, join('', <$fh>));
      @data = grep(!/^--/, @data);
      @data = split(/;/, join('', @data));
      close($fh);
      @data = grep { $_ && $_ !~ /^-- / } @data;
      @data = grep { $_ !~ /^(BEGIN TRANACTION|COMMIT)/m } @data;
      
      $self->_filedata(\@data);
      $self->backup() if($self->do_backup);

      $self->txn_do(sub {
        $self->do_upgrade();
      });
    }

    my $vtable = $self->{vschema}->resultset('Table');
    $vtable->create({ Version => $self->schema_version,
                      Installed => strftime("%Y-%m-%d %H:%M:%S", gmtime())
                      });

}

sub do_upgrade
{
    my ($self) = @_;

    ## overridable sub, per default just run all the commands.
    $self->run_upgrade(qr/create/i);
    $self->run_upgrade(qr/alter table .*? add/i);
    $self->run_upgrade(qr/alter table .*? (?!drop)/i);
    $self->run_upgrade(qr/alter table .*? drop/i);
    $self->run_upgrade(qr/drop/i);
}

sub run_upgrade
{
    my ($self, $stm) = @_;
#    print "Reg: $stm\n";
    my @statements = grep { $_ =~ $stm } @{$self->_filedata};
#    print "Statements: ", join("\n", @statements), "\n";
    $self->_filedata([ grep { $_ !~ /$stm/i } @{$self->_filedata} ]);

    for (@statements)
    {
        $self->storage->debugobj->query_start($_) if $self->storage->debug;
        $self->storage->dbh->do($_) or warn "SQL was:\n $_";
        $self->storage->debugobj->query_end($_) if $self->storage->debug;
    }

    return 1;
}

1;

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

  sub backup
  {
    my ($self) = @_;
    # my special backup process
  }

  sub upgrade
  {
    my ($self) = @_;

    ## overridable sub, per default just runs all the commands.

    $self->run_upgrade(qr/create/i);
    $self->run_upgrade(qr/alter table .*? add/i);
    $self->run_upgrade(qr/alter table .*? (?!drop)/i);
    $self->run_upgrade(qr/alter table .*? drop/i);
    $self->run_upgrade(qr/drop/i);
    $self->run_upgrade(qr//i);   
  }

=head1 DESCRIPTION

This module is a component designed to extend L<DBIx::Class::Schema>
classes, to enable them to upgrade to newer schema layouts. To use this
module, you need to have called C<create_ddl_dir> on your Schema to
create your upgrade files to include with your delivery.

A table called I<SchemaVersions> is created and maintained by the
module. This contains two fields, 'Version' and 'Installed', which
contain each VERSION of your Schema, and the date+time it was installed.

If you would like to influence which levels of version change need
upgrades in your Schema, you can override the method C<ddl_filename>
in L<DBIx::Class::Schema>. Return a false value if there is no upgrade
path between the two versions supplied. By default, every change in
your VERSION is regarded as needing an upgrade.

The actual upgrade is called manually by calling C<upgrade> on your
schema object. Code is run at connect time to determine whether an
upgrade is needed, if so, a warning "Versions out of sync" is
produced.

NB: At the moment, SQLite upgrading is rather spotty, as SQL::Translator::Diff
returns SQL statements that SQLite does not support.


=head1 METHODS

=head2 backup

This is an overwritable method which is called just before the upgrade, to
allow you to make a backup of the database. Per default this method attempts
to call C<< $self->storage->backup >>, to run the standard backup on each
database type. 

This method should return the name of the backup file, if appropriate..

=head2 upgrade

This is the main upgrade method which calls the overridable do_upgrade and
also handles the backups and updating of the SchemaVersion table.

=head2 do_upgrade

This is an overwritable method used to run your upgrade. The freeform method
allows you to run your upgrade any way you please, you can call C<run_upgrade>
any number of times to run the actual SQL commands, and in between you can
sandwich your data upgrading. For example, first run all the B<CREATE>
commands, then migrate your data from old to new tables/formats, then 
issue the DROP commands when you are finished.

=head2 run_upgrade

 $self->run_upgrade(qr/create/i);

Runs a set of SQL statements matching a passed in regular expression. The
idea is that this method can be called any number of times from your
C<upgrade> method, running whichever commands you specify via the
regex in the parameter.

=head2 upgrade_directory

Use this to set the directory your upgrade files are stored in.

=head2 backup_directory

Use this to set the directory you want your backups stored in.

=head2 schema_version

Returns the current schema class' $VERSION; does -not- use $schema->VERSION
since that varies in results depending on if version.pm is installed, and if
so the perl or XS versions. If you want this to change, bug the version.pm
author to make vpp and vxs behave the same.

=head1 AUTHOR

Jess Robinson <castaway@desert-island.demon.co.uk>
