use strict;
use warnings;

use 5.008001;
use inc::Module::Install 1.00;

##
## DO NOT USE THIS HACK IN YOUR DISTS!!! (it makes #toolchain sad)
##
# get cpanX --installdeps . to behave in a checkout (most users do not expect
# the deps for a full test suite run, and if they do - there's MI::AutoInstall
# for that)
BEGIN {
  $Module::Install::AUTHOR = 0 if (grep { $ENV{"PERL5_${_}_IS_RUNNING"} } (qw/CPANM CPANPLUS CPAN/) );
}

name     'DBIx-Class';
perl_version '5.008001';
all_from 'lib/DBIx/Class.pm';

tests_recursive (qw|
    t
|);

install_script (qw|
    script/dbicadmin
|);

homepage 'http://www.dbix-class.org/';
resources 'IRC'         => 'irc://irc.perl.org/#dbix-class';
resources 'license'     => 'http://dev.perl.org/licenses/';
resources 'repository'  => 'git://git.shadowcat.co.uk/dbsrgits/DBIx-Class.git';
resources 'MailingList' => 'http://lists.scsys.co.uk/cgi-bin/mailman/listinfo/dbix-class';
resources 'bugtracker'  => 'http://rt.cpan.org/NoAuth/Bugs.html?Dist=DBIx-Class';

###
### DO NOT ADD OPTIONAL DEPENDENCIES HERE, EVEN AS recommends()
### All of them *MUST* go to DBIx::Class::Optional::Dependencies
###
my $runtime_requires = {
  # FIXME - temporary, needs throwing out for something more efficient
  'Data::Compare'            => '1.22',

  # DBI itself should be capable of installation and execution in pure-perl
  # mode. However it has never been tested yet, so consider XS for the time
  # being
  'DBI'                      => '1.57',

  # XS (or XS-dependent) libs
  'Sub::Name'                => '0.04',

  # pure-perl (FatPack-able) libs
  'Class::Accessor::Grouped' => '0.10002',
  'Class::C3::Componentised' => '1.0009',
  'Class::Inspector'         => '1.24',
  'Config::Any'              => '0.20',
  'Context::Preserve'        => '0.01',
  'Data::Dumper::Concise'    => '2.020',
  'Data::Page'               => '2.00',
  'Hash::Merge'              => '0.12',
  'MRO::Compat'              => '0.09',
  'Module::Find'             => '0.06',
  'namespace::clean'         => '0.20',
  'Path::Class'              => '0.18',
  'Scope::Guard'             => '0.03',
  'SQL::Abstract'            => '1.72',
  'Try::Tiny'                => '0.04',

  # dual-life corelibs needing a specific bugfixed version
  'File::Path'               => '2.07',
};

my $build_requires = {
  # needed for testing only, not for operation
  # we will move away from this dep eventually, perhaps to DBD::CSV or something
  'DBD::SQLite'              => '1.29',
};

my $test_requires = {
  'File::Temp'               => '0.22',
  'Test::Exception'          => '0.31',
  'Test::Warn'               => '0.21',
  'Test::More'               => '0.94',
  # not sure if this is necessary at all, ask schwern some day
  'Test::Builder'            => '0.94',

  # this is already a dep of n::c, but just in case - used by t/55namespaces_cleaned.t
  # remove and do a manual glob-collection if n::c is no longer a dep
  'Package::Stash'           => '0.28',
};

# Bail out on parallel testing
if (
  ($ENV{HARNESS_OPTIONS}||'') =~ / (?: ^ | \: ) j(\d+) /x
    and
  $1 > 1
) { die <<EOP }

******************************************************************************
******************************************************************************
***                                                                        ***
***      PARALLEL TESTING DETECTED ( \$ENV{HARNESS_OPTIONS} = 'j$1' )        ***
***                                                                        ***
*** DBIC tests WILL FAIL. It is harder to make them parallel-friendly than ***
*** it should be (though work is underway). In the meantime you will have  ***
*** to adjust your environment and re-run the installation. Sorry!         ***
***                                                                        ***
******************************************************************************
******************************************************************************

EOP

# this is so we can order requires alphabetically
# copies are needed for potential author requires injection
my $reqs = {
  build_requires => { %$build_requires },
  requires => { %$runtime_requires },
  test_requires => { %$test_requires },
};

# only do author-includes if not part of a `make` run
if ($Module::Install::AUTHOR  and ! $ENV{MAKELEVEL}) {
  # get options here, make $args available to all snippets
  require Getopt::Long;
  my $getopt = Getopt::Long::Parser->new(
    config => [qw/gnu_getopt bundling_override no_ignore_case pass_through/]
  );
  my $args = {
    skip_author_deps => undef,
  };
  $getopt->getoptions($args, qw/
    skip_author_deps|skip-author-deps
  /);
  if (@ARGV) {
    warn "\nIgnoring unrecognized option(s): @ARGV\n\n";
  }

  require File::Spec;
  # string-eval, not do(), because we need to provide the
  # $reqs and $*_requires lexicals to the included file
  # (some includes *do* modify $reqs above)
  for (sort glob ( File::Spec->catfile('maint', 'Makefile.PL.inc', '*') ) ) {
    eval scalar do { local (@ARGV, $/) = $_; <> }
      or die ($@ || $!);
  }
}
else {
  # make sure this Makefile can not be used to make a dist
  # (without the author includes there are no meta cleanup, no sanity checks, etc)
  postamble <<EOP;
.PHONY: nonauthor_stop_distdir_creation
create_distdir: nonauthor_stop_distdir_creation
nonauthor_stop_distdir_creation:
\t\$(NOECHO) \$(ECHO) Creation of dists in non-author mode is not allowed
\t\$(NOECHO) \$(FALSE)
EOP
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

# author-mode or not - this is where we show a list of missing deps
# IFF we are running interactively
auto_install();

WriteAll();
