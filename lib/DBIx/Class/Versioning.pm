package DBIx::Class::Version::Table;
use base 'DBIx::Class';
use strict;
use warnings;

__PACKAGE__->load_components(qw/ Core/);
__PACKAGE__->table('SchemaVersions');

__PACKAGE__->add_columns
    ( 'Version' => {
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
package DBIx::Class::Versioning;

use strict;
use warnings;
use base 'DBIx::Class';
use POSIX 'strftime';
use Data::Dumper;
# use DBIx::Class::Version;

__PACKAGE__->mk_classdata('_filedata');
__PACKAGE__->mk_classdata('upgrade_directory');

sub on_connect
{
    my ($self) = @_;
    print "on_connect\n";
    my $vschema = DBIx::Class::Version->connect(@{$self->storage->connect_info()});
    my $vtable = $vschema->resultset('Table');
    my $pversion;
    if(!$self->exists($vtable))
    {
        print "deploying.. \n";
        $vschema->storage->debug(1);
        print "Debugging is: ", $vschema->storage->debug, "\n";
        $vschema->deploy();
        $pversion = 0;
    }
    else
    {
        $pversion = $vtable->search(undef, 
                                    { select => [
                                             'Version',
                                             { 'max' => 'Installed' },
                                             ],
                                      group_by => [ 'Version' ],
                                      })->first;
        $pversion = $pversion->Version if($pversion);
    }
    if($pversion eq $self->VERSION)
    {
        print "This version is already installed\n";
        return 1;
    }

    
    $vtable->create({ Version => $self->VERSION,
                      Installed => strftime("%Y-%m-%d %H:%M:%S", gmtime())
                      });

    if(!$pversion)
    {
        print "No previous version found, skipping upgrade\n";
        return 1;
    }

    my $file = $self->ddl_filename($self->upgrade_directory,
                                   $self->storage->sqlt_type,
                                   $self->VERSION
                                   );
    $file =~ s/@{[ $self->VERSION ]}/"${pversion}-" . $self->VERSION/e;
    if(!-f $file)
    {
        warn "Upgrade not possible, no upgrade file found ($file)\n";
        return;
    }
    print "Found Upgrade file: $file\n";
    my $fh;
    open $fh, "<$file" or warn("Can't open upgrade file, $file ($!)");
    my @data = split(/;\n/, join('', <$fh>));
    close($fh);
    @data = grep { $_ && $_ !~ /^-- / } @data;
    @data = grep { $_ !~ /^(BEGIN TRANACTION|COMMIT)/m } @data;
    print "Commands: ", join("\n", @data), "\n";
    $self->_filedata(\@data);

    $self->backup();
    $self->upgrade();

# X Create version table if not exists?
# Make backup
# Run create statements
# Run post-create callback
# Run alter/drop statement
# Run post-alter callback
}

sub exists
{
    my ($self, $rs) = @_;

    eval {
        $rs->search({ 1, 0 })->count;
    };

    return 0 if $@;

    return 1;
}

sub backup
{
    my ($self) = @_;
}

sub upgrade
{
    my ($self) = @_;

    ## overridable sub, per default just run all the commands.

    $self->run_upgrade(qr/create/i);
    $self->run_upgrade(qr/alter table .*? add/i);
    $self->run_upgrade(qr/alter table .*? (?!drop)/i);
    $self->run_upgrade(qr/alter table .*? drop/i);
    $self->run_upgrade(qr/drop/i);
    $self->run_upgrade(qr//i);
}


sub run_upgrade
{
    my ($self, $stm) = @_;
    print "Reg: $stm\n";
    my @statements = grep { $_ =~ $stm } @{$self->_filedata};
#    print "Statements: ", join("\n", @statements), "\n";
    $self->_filedata([ grep { $_ !~ /$stm/i } @{$self->_filedata} ]);

    for (@statements)
    {
        $self->storage->debugfh->print("$_\n") if $self->storage->debug;
        print "Running \n>>$_<<\n";
        $self->storage->dbh->do($_) or warn "SQL was:\n $_";
    }

    return 1;
}
