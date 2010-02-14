use inc::Module::Install 0.93;
use strict;
use warnings;
use POSIX ();

use 5.008001;

use FindBin;
use lib "$FindBin::Bin/lib";

###
### DO NOT ADD OPTIONAL DEPENDENCIES HERE, EVEN AS recommends()
### All of them should go to DBIx::Class::Optional::Dependencies
###


name     'DBIx-Class';
perl_version '5.008001';
all_from 'lib/DBIx/Class.pm';

my $build_requires = {
  'DBD::SQLite'              => '1.25',
};

my $test_requires = {
  'File::Temp'               => '0.22',
  'Test::Builder'            => '0.33',
  'Test::Deep'               => '0',
  'Test::Exception'          => '0',
  'Test::More'               => '0.92',
  'Test::Warn'               => '0.21',
};

my $runtime_requires = {
  # Core
  'List::Util'               => '0',
  'Scalar::Util'             => '0',
  'Storable'                 => '0',

  # Dependencies
  'Carp::Clan'               => '6.0',
  'Class::Accessor::Grouped' => '0.09002',
  'Class::C3::Componentised' => '1.0005',
  'Class::Inspector'         => '1.24',
  'Data::Page'               => '2.00',
  'DBI'                      => '1.609',
  'MRO::Compat'              => '0.09',
  'Module::Find'             => '0.06',
  'Path::Class'              => '0.18',
  'Scope::Guard'             => '0.03',
  'SQL::Abstract'            => '1.61',
  'SQL::Abstract::Limit'     => '0.13',
  'Sub::Name'                => '0.04',
  'Data::Dumper::Concise'    => '1.000',
};

# this is so we can order requires alphabetically
# copies are needed for author requires injection
my $reqs = {
  build_requires => { %$build_requires },
  requires => { %$runtime_requires },
  test_requires => { %$test_requires },
};

# re-build README and require extra modules for testing if we're in a checkout
if ($Module::Install::AUTHOR) {

  print "Regenerating README\n";
  system('pod2text lib/DBIx/Class.pm > README');

  if (-f 'MANIFEST') {
    print "Removing MANIFEST\n";
    unlink 'MANIFEST';
  }

  print "Regenerating Optional/Dependencies.pod\n";
  require DBIx::Class::Optional::Dependencies;
  DBIx::Class::Optional::Dependencies->_gen_pod;

# FIXME Disabled due to unsolved issues, ask theorbtwo
#  require Module::Install::Pod::Inherit;
#  PodInherit();

  warn <<'EOW';
******************************************************************************
******************************************************************************
***                                                                        ***
*** AUTHOR MODE: all optional test dependencies converted to hard requires ***
***                                                                        ***
******************************************************************************
******************************************************************************

EOW

  $reqs->{test_requires} = {
    %{$reqs->{test_requires}},
    %{DBIx::Class::Optional::Dependencies->_all_optional_requirements},
  };
}

# compose final req list, for alphabetical ordering
my %final_req;
for my $rtype (keys %$reqs) {
  for my $mod (keys %{$reqs->{$rtype}} ) {

    # sanity check req duplications
    if ($final_req{$mod}) {
      die "$mod specified as both a '$rtype' and a '$final_req{$mod}[0]'\n";
    }

    $final_req{$mod} = [ $rtype, $reqs->{$rtype}{$mod}||0 ],
  }
}

# actual require
for my $mod (sort keys %final_req) {
  my ($rtype, $ver) = @{$final_req{$mod}};
  no strict 'refs';
  $rtype->($mod, $ver);
}

install_script (qw|
    script/dbicadmin
|);

tests_recursive (qw|
    t
|);

resources 'IRC'         => 'irc://irc.perl.org/#dbix-class';
resources 'license'     => 'http://dev.perl.org/licenses/';
resources 'repository'  => 'http://dev.catalyst.perl.org/repos/bast/DBIx-Class/';
resources 'MailingList' => 'http://lists.scsys.co.uk/cgi-bin/mailman/listinfo/dbix-class';

# Deprecated/internal modules need no exposure
no_index directory => $_ for (qw|
  lib/DBIx/Class/SQLAHacks
  lib/DBIx/Class/PK/Auto
|);
no_index package => $_ for (qw/
  DBIx::Class::Storage::DBI::AmbiguousGlob
  DBIx::Class::SQLAHacks DBIx::Class::Storage::DBIHacks
/);


auto_install();

WriteAll();


# Re-write META.yml to _exclude_ all forced requires (we do not want to ship this)
if ($Module::Install::AUTHOR) {

  # FIXME test_requires is not yet part of META
  my %original_build_requires = ( %$build_requires, %$test_requires );

  print "Regenerating META with author requires excluded\n";
  Meta->{values}{build_requires} = [ grep
    { exists $original_build_requires{$_->[0]} }
   ( @{Meta->{values}{build_requires}} )
  ];

  Meta->write;
}
