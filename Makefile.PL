use strict;
use warnings;

use 5.008001;
use inc::Module::Install 1.06;

##
## DO NOT USE THIS HACK IN YOUR DISTS!!! (it makes #toolchain sad)
##
# get cpanX --installdeps . to behave in a checkout (most users do not expect
# the deps for a full test suite run, and if they do - there's MI::AutoInstall
# for that)
BEGIN {
  $Module::Install::AUTHOR = 0 if (grep { $ENV{"PERL5_${_}_IS_RUNNING"} } (qw/CPANM CPANPLUS CPAN/) );
  makemaker_args( NORECURS => 1 );
}

homepage 'http://www.dbix-class.org/';
resources 'IRC'         => 'irc://irc.perl.org/#dbix-class';
resources 'license'     => 'http://dev.perl.org/licenses/';
resources 'repository'  => 'https://github.com/dbsrgits/DBIx-Class';
resources 'MailingList' => 'http://lists.scsys.co.uk/cgi-bin/mailman/listinfo/dbix-class';
resources 'bugtracker'  => 'http://rt.cpan.org/NoAuth/Bugs.html?Dist=DBIx-Class';

name     'DBIx-Class';
perl_version '5.008001';
all_from 'lib/DBIx/Class.pm';
Meta->{values}{x_authority} = 'cpan:RIBASUSHI';

tests_recursive (qw|
    t
|);

install_script (qw|
    script/dbicadmin
|);

###
### DO NOT ADD OPTIONAL DEPENDENCIES HERE, EVEN AS recommends()
### All of them *MUST* go to DBIx::Class::Optional::Dependencies
###
my $runtime_requires = {
  # FIXME - temporary workaround for RT#83143 (Path::Class)
  'File::Spec'               => '3.30',

  # FIXME - temporary, needs throwing out for something more efficient
  'Data::Compare'            => '1.22',

  # DBI itself should be capable of installation and execution in pure-perl
  # mode. However it has never been tested yet, so consider XS for the time
  # being
  'DBI'                      => '1.57',

  # on older versions first() leaks
  # for the time being make it a hard dep - when we get
  # rid of Sub::Name will revisit this (possibility is
  # to use Devel::HideXS to force the pure-perl version
  # or something like that)
  'List::Util'               => '1.16',

  # XS (or XS-dependent) libs
  'Sub::Name'                => '0.04',

  # pure-perl (FatPack-able) libs
  'Class::Accessor::Grouped' => '0.10009',
  'Class::C3::Componentised' => '1.0009',
  'Class::Inspector'         => '1.24',
  'Config::Any'              => '0.20',
  'Context::Preserve'        => '0.01',
  'Data::Dumper::Concise'    => '2.020',
  'Data::Page'               => '2.00',
  'Devel::GlobalDestruction' => '0.09',
  'Hash::Merge'              => '0.12',
  'Moo'                      => '1.000006',
  'MRO::Compat'              => '0.12',
  'Module::Find'             => '0.07',
  'namespace::clean'         => '0.24',
  'Path::Class'              => '0.18',
  'Scope::Guard'             => '0.03',
  'SQL::Abstract'            => '1.73',
  'Try::Tiny'                => '0.07',

  # Technically this is not a core dependency - it is only required
  # by the MySQL codepath. However this particular version is bundled
  # since 5.10.0 and is a pure-perl module anyway - let it slide
  'Text::Balanced'           => '2.00',
};

my $build_requires = {
  # needed for testing only, not for operation
  # we will move away from this dep eventually, perhaps to DBD::CSV or something
  'DBD::SQLite'              => '1.29',
};

my $test_requires = {
  'File::Temp'               => '0.22',
  'Test::Deep'               => '0.101',
  'Test::Exception'          => '0.31',
  'Test::Warn'               => '0.21',
  'Test::More'               => '0.94',
  # not sure if this is necessary at all, ask schwern some day
  'Test::Builder'            => '0.94',

  # this is already a dep of n::c, but just in case - used by t/55namespaces_cleaned.t
  # remove and do a manual glob-collection if n::c is no longer a dep
  'Package::Stash'           => '0.28',
};

# make strictures.pm happy (DO NOT LIKE, TOO MUCH XS!)
# (i.e. what if the .git/.svn is *not* because of DBIC?)
#
# Note - this is added as test_requires *directly*, so it gets properly
# excluded on META.yml cleansing
if (-e '.git' or -e '.svn') {
  test_requires 'indirect'              => '0.25';
  test_requires 'multidimensional'      => '0.008';
  test_requires 'bareword::filehandles' => '0.003';
}

# if the user has this env var set and no SQLT installed, tests will fail
# same rationale for direct test_requires as the strictures stuff above
# (even though no dist will be created from this)
# we force this req regarless of author_deps, worst case scenario it will
# be specified twice
if ($ENV{DBICTEST_SQLT_DEPLOY}) {
  local @INC = ('lib', @INC);
  require DBIx::Class::Optional::Dependencies;
  my $dep_req = DBIx::Class::Optional::Dependencies->req_list_for('deploy');
  for (keys %$dep_req) {
    test_requires ($_ => $dep_req->{$_})
  }
}

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

  # We need the MM facilities to generate the pieces for the final MM run.
  # Just instantiate a throaway object here
  my $mm_proto = ExtUtils::MakeMaker->new({
    NORECURS => 1,
    NAME => Meta->name || die 'The Module::Install metadata must be available at this point but is not - did you rearrange the Makefile.PL...?',
  });

  # Crutch for DISTBUILDING_IN_HELL
  # Spits back a working dos2unix snippet to be used on the supplied path(s)
  # Ironically EUMM's dos2unix is broken on win32 itself - it does
  # not take into account the CRLF layer present on win32
  my $crlf_fixup = sub {
    return '' unless ($^O eq 'MSWin32' or $^O eq 'cygwin');
    my $targets = join ', ', map { "q($_)" } @_;
    "\t" . $mm_proto->oneliner( qq(\$ENV{PERLIO}='unix' and system( \$^X, qw( -MExtUtils::Command -e dos2unix -- ), $targets ) ) );
  };

  # we are in the process of (re)writing the makefile - some things we
  # call below very well may fail
  local $ENV{DBICTEST_NO_MAKEFILE_VERIFICATION} = 1;

  require File::Spec;
  # string-eval, not do(), because we need to provide the
  # $mm_proto, $reqs and $*_requires lexicals to the included file
  # (some includes *do* modify $reqs above)
  for my $inc (sort glob ( File::Spec->catfile('maint', 'Makefile.PL.inc', '*') ) ) {
    my $src = do { local (@ARGV, $/) = $inc; <> } or die $!;
    eval "use warnings; use strict; $src" or die sprintf
      "Failed execution of %s: %s\n",
      $inc,
      ($@ || $! || 'Unknown error'),
    ;
  }
}
else {
  # make sure this Makefile can not be used to make a dist
  # (without the author includes there are no meta cleanup, no sanity checks, etc)
  postamble <<EOP;
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
